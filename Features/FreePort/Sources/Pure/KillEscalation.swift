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
        /// `undeliveredTargets` are the pids whose SIGKILL never landed — macOS
        /// refused it, or the call failed. Carried this far because a process
        /// that was never signalled cannot be said to have survived a signal.
        /// This is the SIGKILL round's result only: a pid refused at SIGTERM
        /// whose SIGKILL then succeeded was signalled, and folding the earlier
        /// refusal in would report it as untouched.
        case afterForceKill(approvedTargets: Set<Int32>, undeliveredTargets: Set<Int32>)
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
        let targets = signalableIdentifiers(among: snapshot.holders, stage: stage, currentUser: currentUser)
        guard !targets.isEmpty else {
            return .report(outcomeWithNothingToSignal(holders: snapshot.holders, currentUser: currentUser))
        }
        switch stage {
        case .initial:
            return .terminate(targets)
        case .afterTermination:
            return .forceKill(targets)
        case .afterForceKill(_, let undeliveredTargets):
            // Only the pids actually signalled can be said to have survived. A
            // stranger that appeared during the settling window is reported by
            // the branch above, under its own outcome.
            let signalledTargets = Set(targets)
            let survivors = snapshot.holders.filter { signalledTargets.contains($0.processIdentifier) }
            return .report(
                .stillHeld(
                    signalled: survivors.filter { !undeliveredTargets.contains($0.processIdentifier) },
                    undelivered: survivors.filter { undeliveredTargets.contains($0.processIdentifier) },
                    // Whatever else is on the port: a stranger that arrived
                    // during the settling window, or another user's process.
                    // Never signalled, but still the answer to "is it free?".
                    untouched: snapshot.holders.filter { !signalledTargets.contains($0.processIdentifier) }
                )
            )
        }
    }

    /// Sorted and deduplicated: `lsof` reports a pid once per socket, and one
    /// signal per process is both sufficient and all the user agreed to.
    private static func signalableIdentifiers(
        among holders: [ListeningProcess],
        stage: Stage,
        currentUser: String
    ) -> [Int32] {
        let approvedTargets = approvedTargets(for: stage)
        let signalable = holders.filter { holder in
            guard holder.user == currentUser else {
                return false
            }
            return approvedTargets?.contains(holder.processIdentifier) ?? true
        }
        return Set(signalable.map(\.processIdentifier)).sorted()
    }

    /// `nil` before anything has been signalled — there is nothing to bound yet,
    /// because the dialog that names the targets has not been shown.
    private static func approvedTargets(for stage: Stage) -> Set<Int32>? {
        switch stage {
        case .initial:
            return nil
        case .afterTermination(let approvedTargets), .afterForceKill(let approvedTargets, _):
            return approvedTargets
        }
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
