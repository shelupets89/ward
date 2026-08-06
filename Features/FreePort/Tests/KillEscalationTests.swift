import Testing
@testable import FreePort

/// The escalation is the part that can destroy work, so every case here is a
/// safety property rather than a convenience: what gets signalled, what only
/// gets reported, and when the machine stops.
struct KillEscalationTests {
    private let currentUser = "dimashelupets"

    private func ownedProcess(
        command: String = "node",
        pid: Int32,
        port: UInt16 = 3001
    ) -> ListeningProcess {
        return ListeningProcess(command: command, processIdentifier: pid, user: currentUser, port: port)
    }

    private func rootProcess(command: String = "sshd", pid: Int32, port: UInt16 = 22) -> ListeningProcess {
        return ListeningProcess(command: command, processIdentifier: pid, user: "root", port: port)
    }

    private func snapshot(_ holders: [ListeningProcess], isOccupied: Bool? = nil) -> PortSnapshot {
        return PortSnapshot(holders: holders, isOccupied: isOccupied ?? !holders.isEmpty)
    }

    private func nextStep(
        stage: KillEscalation.Stage,
        snapshot portSnapshot: PortSnapshot
    ) -> KillEscalation.Step {
        return KillEscalation.nextStep(stage: stage, snapshot: portSnapshot, currentUser: currentUser)
    }

    // MARK: - Nothing to do

    @Test("Never signals anything when nothing was listening")
    func reportsNothingWasListening() {
        let step = nextStep(stage: .initial, snapshot: snapshot([], isOccupied: false))
        #expect(step == .report(.nothingWasListening))
    }

    @Test("Reports a port held by someone else rather than claiming it was free")
    func reportsPortHeldByAProcessItCannotSee() {
        let step = nextStep(stage: .initial, snapshot: snapshot([], isOccupied: true))
        #expect(step == .report(.heldByAnotherUser(visibleHolders: [])))
    }

    @Test("Reports a root-held port instead of signalling it")
    func neverSignalsAProcessOwnedByAnotherUser() {
        let daemon = rootProcess(pid: 431)
        let step = nextStep(stage: .initial, snapshot: snapshot([daemon]))
        #expect(step == .report(.heldByAnotherUser(visibleHolders: [daemon])))
    }

    @Test("Reports every holder when a port mixes owned and root processes but none can be signalled")
    func reportsMixedOwnershipWithoutSignalling() {
        let daemons = [rootProcess(pid: 431), rootProcess(command: "launchd", pid: 1)]
        let step = nextStep(stage: .initial, snapshot: snapshot(daemons))
        #expect(step == .report(.heldByAnotherUser(visibleHolders: daemons)))
    }

    // MARK: - Termination first

    @Test("Sends SIGTERM before anything else")
    func terminatesBeforeForceKilling() {
        let step = nextStep(stage: .initial, snapshot: snapshot([ownedProcess(pid: 26036)]))
        #expect(step == .terminate([26036]))
    }

    @Test("Signals only the processes this user owns")
    func terminatesOnlyOwnedProcesses() {
        let holders = [ownedProcess(pid: 26036), rootProcess(pid: 431, port: 3001)]
        let step = nextStep(stage: .initial, snapshot: snapshot(holders))
        #expect(step == .terminate([26036]))
    }

    @Test("Signals each pid once even when it holds the port twice")
    func terminatesEachProcessOnce() {
        let duplicated = [ownedProcess(pid: 26036), ownedProcess(pid: 26036)]
        let step = nextStep(stage: .initial, snapshot: snapshot(duplicated))
        #expect(step == .terminate([26036]))
    }

    @Test("Signals a multi-process port in a stable order")
    func terminatesInStableOrder() {
        let holders = [ownedProcess(pid: 900), ownedProcess(pid: 100), ownedProcess(pid: 500)]
        let step = nextStep(stage: .initial, snapshot: snapshot(holders))
        #expect(step == .terminate([100, 500, 900]))
    }

    // MARK: - Escalation after the grace period

    @Test("Stops without SIGKILL when SIGTERM already freed the port")
    func stopsWhenTerminationFreedThePort() {
        let step = nextStep(
            stage: .afterTermination(approvedTargets: [26036]),
            snapshot: snapshot([], isOccupied: false)
        )
        #expect(step == .report(.freed))
    }

    @Test("Escalates to SIGKILL for the survivors of SIGTERM")
    func escalatesToForceKillForSurvivors() {
        let survivors = [ownedProcess(pid: 26036)]
        let step = nextStep(stage: .afterTermination(approvedTargets: [26036, 26037]), snapshot: snapshot(survivors))
        #expect(step == .forceKill([26036]))
    }

    @Test("Never force-kills a process the user was not shown")
    func neverForceKillsAnUnapprovedProcess() {
        let squatter = ownedProcess(command: "python3", pid: 55555)
        let step = nextStep(stage: .afterTermination(approvedTargets: [26036]), snapshot: snapshot([squatter]))
        #expect(step == .report(.takenByAnotherProcess([squatter])))
    }

    @Test("Force-kills the approved survivor and leaves an unapproved squatter beside it")
    func forceKillsOnlyTheApprovedSurvivorAmongMixedHolders() {
        let approvedSurvivor = ownedProcess(pid: 26036)
        let squatter = ownedProcess(command: "python3", pid: 55555)
        let step = nextStep(
            stage: .afterTermination(approvedTargets: [26036]),
            snapshot: snapshot([approvedSurvivor, squatter])
        )
        #expect(step == .forceKill([26036]))
    }

    @Test("Does not describe a never-signalled process as having survived a signal")
    func distinguishesASquatterFromASurvivor() {
        let squatter = ownedProcess(command: "python3", pid: 55555)
        let afterTermination = nextStep(
            stage: .afterTermination(approvedTargets: [26036]),
            snapshot: snapshot([squatter])
        )
        let afterForceKill = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: []),
            snapshot: snapshot([squatter])
        )
        #expect(afterTermination == .report(.takenByAnotherProcess([squatter])))
        #expect(afterForceKill == .report(.takenByAnotherProcess([squatter])))
    }

    @Test("Names a late arrival as untouched rather than as a survivor — and never omits it")
    func separatesALateArrivalFromASurvivorWithoutDroppingIt() {
        let survivor = ownedProcess(pid: 26036)
        let lateArrival = ownedProcess(command: "python3", pid: 55555)
        let step = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: []),
            snapshot: snapshot([survivor, lateArrival])
        )
        #expect(step == .report(.stillHeld(signalled: [survivor], undelivered: [], untouched: [lateArrival])))
    }

    /// A process that closes its listening socket while handling SIGTERM and
    /// rebinds afterwards is missing from the snapshot the SIGKILL batch is
    /// built from, so it never receives one — but it is back on the port by the
    /// time the result is read. Classifying by "approved and present now" made
    /// it indistinguishable from a process that took a SIGKILL and lived.
    @Test("Never says a process survived SIGKILL when it was not in the SIGKILL batch")
    func neverClaimsASignalTheBatchNeverIncluded() {
        let rebounder = ownedProcess(pid: 26036)
        let killedTarget = ownedProcess(command: "python3", pid: 26037)
        let step = nextStep(
            // Only 26037 was reachable when the batch was built, so only it was signalled.
            stage: .afterForceKill(forceKilledTargets: [26037], undeliveredTargets: []),
            snapshot: snapshot([rebounder, killedTarget])
        )
        #expect(
            step == .report(
                .stillHeld(signalled: [killedTarget], undelivered: [], untouched: [rebounder])
            )
        )
    }

    @Test("Accounts for every holder on the port, splitting them three ways")
    func partitionsEveryHolderIntoExactlyOneList() {
        let survivor = ownedProcess(pid: 26036)
        let undeliveredProcess = ownedProcess(command: "coreaudiod", pid: 26037)
        let lateArrival = ownedProcess(command: "python3", pid: 55555)
        let daemon = rootProcess(pid: 431, port: 3001)
        let holders = [survivor, undeliveredProcess, lateArrival, daemon]
        let step = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036, 26037], undeliveredTargets: [26037]),
            snapshot: snapshot(holders)
        )
        guard case .report(.stillHeld(let signalled, let undelivered, let untouched)) = step else {
            Issue.record("expected a stillHeld report, got \(step)")
            return
        }
        #expect(signalled == [survivor])
        #expect(undelivered == [undeliveredProcess])
        #expect(untouched == [lateArrival, daemon])
        #expect(signalled.count + undelivered.count + untouched.count == holders.count)
    }

    @Test("Reports rather than escalating when only another user's process survives")
    func reportsWhenOnlyAnotherUsersProcessSurvives() {
        let daemon = rootProcess(pid: 431, port: 3001)
        let step = nextStep(stage: .afterTermination(approvedTargets: [26036]), snapshot: snapshot([daemon]))
        #expect(step == .report(.heldByAnotherUser(visibleHolders: [daemon])))
    }

    // MARK: - Verification after SIGKILL

    @Test("Confirms the port is free only after re-checking it")
    func reportsFreedAfterForceKill() {
        let step = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: []),
            snapshot: snapshot([], isOccupied: false)
        )
        #expect(step == .report(.freed))
    }

    @Test("Says the kill worked when an invisible process takes the freed port")
    func distinguishesReoccupationFromNeverHavingATarget() {
        let step = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: []),
            snapshot: snapshot([], isOccupied: true)
        )
        #expect(step == .report(.freedThenTakenByAnotherUser))
    }

    @Test("Never describes an undelivered signal as one the process survived")
    func reportsAnUndeliveredSignalSeparately() {
        let protectedProcess = ownedProcess(command: "coreaudiod", pid: 26036)
        let step = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: [26036]),
            snapshot: snapshot([protectedProcess])
        )
        #expect(step == .report(.stillHeld(signalled: [], undelivered: [protectedProcess], untouched: [])))
    }

    @Test("Reports both a wedged survivor and an undelivered one, dropping neither")
    func reportsBothKindsOfSurvivorTogether() {
        let undeliveredProcess = ownedProcess(command: "coreaudiod", pid: 26036)
        let wedgedProcess = ownedProcess(pid: 26037)
        let step = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036, 26037], undeliveredTargets: [26036]),
            snapshot: snapshot([undeliveredProcess, wedgedProcess])
        )
        #expect(step == .report(.stillHeld(signalled: [wedgedProcess], undelivered: [undeliveredProcess], untouched: [])))
    }

    @Test("Reports still-held when survivors outlive SIGKILL")
    func reportsStillHeldWhenSurvivorsPersist() {
        let survivors = [ownedProcess(pid: 26036)]
        let step = nextStep(stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: []), snapshot: snapshot(survivors))
        #expect(step == .report(.stillHeld(signalled: survivors, undelivered: [], untouched: [])))
    }

    @Test("Never escalates past SIGKILL")
    func neverEscalatesPastForceKill() {
        let survivor = ownedProcess(pid: 26036)
        let step = nextStep(stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: []), snapshot: snapshot([survivor]))
        #expect(step == .report(.stillHeld(signalled: [survivor], undelivered: [], untouched: [])))
    }

    @Test("Treats a process that vanished on its own as success, not as an error")
    func treatsAlreadyGoneAsSuccess() {
        let afterTermination = nextStep(
            stage: .afterTermination(approvedTargets: [26036]),
            snapshot: snapshot([], isOccupied: false)
        )
        let afterForceKill = nextStep(
            stage: .afterForceKill(forceKilledTargets: [26036], undeliveredTargets: []),
            snapshot: snapshot([], isOccupied: false)
        )
        #expect(afterTermination == .report(.freed))
        #expect(afterForceKill == .report(.freed))
    }
}
