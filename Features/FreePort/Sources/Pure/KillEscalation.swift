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
        case afterForceKill(approvedTargets: Set<Int32>)
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
        case stillHeld([ListeningProcess])
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
        case .afterForceKill:
            return .report(.stillHeld(snapshot.holders))
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
        case .afterTermination(let approvedTargets), .afterForceKill(let approvedTargets):
            return approvedTargets
        }
    }

    private static func outcomeForFreePort(stage: Stage, isOccupied: Bool) -> Outcome {
        guard !isOccupied else {
            return .heldByAnotherUser(visibleHolders: [])
        }
        switch stage {
        case .initial:
            return .nothingWasListening
        case .afterTermination, .afterForceKill:
            return .freed
        }
    }

    private static func outcomeWithNothingToSignal(
        holders: [ListeningProcess],
        currentUser: String
    ) -> Outcome {
        let isEveryHolderAnotherUsers = holders.allSatisfy { $0.user != currentUser }
        guard isEveryHolderAnotherUsers else {
            return .stillHeld(holders)
        }
        return .heldByAnotherUser(visibleHolders: holders)
    }
}
