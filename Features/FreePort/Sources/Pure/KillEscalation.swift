/// SIGTERM → wait → SIGKILL → verify, as a state machine with no side effects.
///
/// Every way this feature could destroy the wrong thing is a decision made
/// here, where it can be tested, rather than in the code holding the syscall:
///
/// - A process this user does not own is only ever reported. There is no path
///   from any stage to signalling one, so no path to needing `sudo`.
/// - Escalation is bounded by `approvedTargets` — the pids named in the dialog
///   the user accepted. A different process that grabs the port during the
///   grace period is a stranger to that dialog and is left alone.
/// - `freed` requires an actually-empty port, never a signal that returned
///   success.
public enum KillEscalation {
    public enum Stage: Equatable, Sendable {
        case initial
        /// `approvedTargets` are the pids the user was shown and accepted.
        case afterTermination(approvedTargets: Set<Int32>)
        /// `forceKilledTargets` are the pids SIGKILL was actually attempted on,
        /// carried from the caller rather than re-derived here. Re-deriving it
        /// from the current holders was the root of a bug that outlived three
        /// rounds of fixes: a process that closed its socket during the grace
        /// period and rebound afterwards was absent from the SIGKILL batch, yet
        /// looked identical to one that took a SIGKILL and lived.
        ///
        /// `undeliveredTargets` are the subset whose SIGKILL never landed —
        /// macOS refused it, or the call failed. The SIGKILL round's result
        /// only: a pid refused at SIGTERM whose SIGKILL then succeeded *was*
        /// signalled, and folding the earlier refusal in would deny that.
        case afterForceKill(forceKilledTargets: Set<Int32>, undeliveredTargets: Set<Int32>)
    }

    public enum Step: Equatable, Sendable {
        case terminate([Int32])
        case forceKill([Int32])
        case report(Outcome)
    }

    public enum Outcome: Equatable, Sendable {
        case nothingWasListening
        /// `visibleHolders` is empty when `lsof` could not see the holder,
        /// which without root is the usual case for a port owned by root.
        case heldByAnotherUser(visibleHolders: [ListeningProcess])
        case freed
        /// What the user approved is gone, but the port is occupied again by a
        /// holder `lsof` cannot see. Distinct from `heldByAnotherUser`, which
        /// says Ward never had anything to stop here — telling the user that
        /// after a successful kill makes a working action look like a failure.
        case freedThenTakenByAnotherUser
        /// The port is still held, by everything still on it. The three lists
        /// mean different things and the user needs all of them: `signalled`
        /// outlived a delivered SIGKILL, `undelivered` never received one
        /// (macOS refused, or the call failed), `untouched` was never approved
        /// and so was never signalled at all.
        ///
        /// They are one case rather than three outcomes because every earlier
        /// shape here reported a subset and silently dropped the rest — three
        /// times over. "Show everything still on the port" is the same rule as
        /// "show everything about to die", and a partition cannot forget a row.
        case stillHeld(
            signalled: [ListeningProcess],
            undelivered: [ListeningProcess],
            untouched: [ListeningProcess]
        )
        /// The approved processes are gone, but something that was never
        /// signalled is on the port now — typically a supervisor restarting the
        /// server inside the grace period. Kept apart from `stillHeld` because
        /// saying these "survived SIGKILL" would be a plain lie: Ward never sent
        /// them anything.
        case takenByAnotherProcess([ListeningProcess])
    }

    public static func nextStep(stage: Stage, snapshot: PortSnapshot, currentUser: String) -> Step {
        guard !snapshot.holders.isEmpty else {
            return .report(outcomeForFreePort(stage: stage, isOccupied: snapshot.isOccupied))
        }
        switch stage {
        case .initial:
            // No approved set yet — the dialog naming the targets is what this
            // step produces.
            return signalStep(among: snapshot.holders, approvedTargets: nil, currentUser: currentUser) { targets in
                .terminate(targets)
            }
        case .afterTermination(let approvedTargets):
            return signalStep(
                among: snapshot.holders,
                approvedTargets: approvedTargets,
                currentUser: currentUser
            ) { targets in
                .forceKill(targets)
            }
        case .afterForceKill(let forceKilledTargets, let undeliveredTargets):
            // Classifies by what was *done*, so it never asks which pids are
            // signalable now — a different question, and the wrong one here.
            return .report(
                finalOutcome(
                    holders: snapshot.holders,
                    forceKilledTargets: forceKilledTargets,
                    undeliveredTargets: undeliveredTargets,
                    currentUser: currentUser
                )
            )
        }
    }

    private static func signalStep(
        among holders: [ListeningProcess],
        approvedTargets: Set<Int32>?,
        currentUser: String,
        makeStep: ([Int32]) -> Step
    ) -> Step {
        let targets = signalableIdentifiers(
            among: holders,
            approvedTargets: approvedTargets,
            currentUser: currentUser
        )
        guard !targets.isEmpty else {
            return .report(outcomeWithNothingToSignal(holders: holders, currentUser: currentUser))
        }
        return makeStep(targets)
    }

    /// Splits every holder by what actually happened to it. A total partition
    /// of `holders`, keyed on the real SIGKILL batch — not on who could be
    /// signalled now, which would label a process that merely reappeared as one
    /// that withstood a signal nobody sent it.
    private static func finalOutcome(
        holders: [ListeningProcess],
        forceKilledTargets: Set<Int32>,
        undeliveredTargets: Set<Int32>,
        currentUser: String
    ) -> Outcome {
        let wasForceKilled = { (holder: ListeningProcess) in
            forceKilledTargets.contains(holder.processIdentifier)
        }
        let wasUndelivered = { (holder: ListeningProcess) in
            undeliveredTargets.contains(holder.processIdentifier)
        }
        let signalled = holders.filter { wasForceKilled($0) && !wasUndelivered($0) }
        let undelivered = holders.filter { wasForceKilled($0) && wasUndelivered($0) }
        // Nothing Ward signalled is left, so the port belongs entirely to
        // whatever else is on it — which has its own, better-aimed wording.
        guard !signalled.isEmpty || !undelivered.isEmpty else {
            return outcomeWithNothingToSignal(holders: holders, currentUser: currentUser)
        }
        return .stillHeld(
            signalled: signalled,
            undelivered: undelivered,
            untouched: holders.filter { !wasForceKilled($0) }
        )
    }

    /// Sorted and deduplicated: `lsof` reports a pid once per socket, and one
    /// signal per process is both sufficient and all the user agreed to.
    ///
    /// - Parameter approvedTargets: `nil` before anything has been signalled —
    ///   there is nothing to bound yet, because the dialog naming the targets
    ///   has not been shown.
    private static func signalableIdentifiers(
        among holders: [ListeningProcess],
        approvedTargets: Set<Int32>?,
        currentUser: String
    ) -> [Int32] {
        let signalable = holders.filter { holder in
            guard holder.user == currentUser else {
                return false
            }
            return approvedTargets?.contains(holder.processIdentifier) ?? true
        }
        return Set(signalable.map(\.processIdentifier)).sorted()
    }

    /// The port holds nothing this user can see. What that *means* depends on
    /// whether Ward has already acted: before any signal it is someone else's
    /// port, afterwards it is a port Ward successfully freed and something else
    /// took. Reporting the first in place of the second hides a successful kill.
    private static func outcomeForFreePort(stage: Stage, isOccupied: Bool) -> Outcome {
        switch stage {
        case .initial:
            return isOccupied ? .heldByAnotherUser(visibleHolders: []) : .nothingWasListening
        case .afterTermination, .afterForceKill:
            return isOccupied ? .freedThenTakenByAnotherUser : .freed
        }
    }

    /// Reached only when nothing on the port may be signalled — either it all
    /// belongs to someone else, or it is this user's but was never approved.
    /// Neither has been sent a signal, so neither may be reported as surviving one.
    private static func outcomeWithNothingToSignal(
        holders: [ListeningProcess],
        currentUser: String
    ) -> Outcome {
        let isEveryHolderAnotherUsers = holders.allSatisfy { $0.user != currentUser }
        guard isEveryHolderAnotherUsers else {
            return .takenByAnotherProcess(holders)
        }
        return .heldByAnotherUser(visibleHolders: holders)
    }
}
