import Testing
@testable import FreePort

/// The confirmation dialog is the only thing standing between a click and lost
/// work, so its contents are asserted rather than eyeballed.
struct FreePortMessagesTests {
    private let server = ListeningProcess(command: "node", processIdentifier: 26036, user: "501", port: 3001)
    private let worker = ListeningProcess(command: "python3", processIdentifier: 26037, user: "501", port: 3001)
    private let daemon = ListeningProcess(command: "sshd", processIdentifier: 431, user: "0", port: 3001)

    // MARK: - Confirmation

    @Test("Names every process that is about to be killed")
    func namesEveryTarget() {
        let confirmation = FreePortMessages.confirmation(port: 3001, targets: [server, worker], leftAlone: [])
        #expect(confirmation.body.contains("node (pid 26036)"))
        #expect(confirmation.body.contains("python3 (pid 26037)"))
    }

    @Test("Never reduces the targets to a bare count")
    func neverDescribesTargetsAsACount() {
        let confirmation = FreePortMessages.confirmation(port: 3001, targets: [server, worker], leftAlone: [])
        #expect(!confirmation.body.contains("2 processes"))
    }

    @Test("Names the port in the question so a mistyped port is visible")
    func namesThePortBeingFreed() {
        let confirmation = FreePortMessages.confirmation(port: 5000, targets: [server], leftAlone: [])
        #expect(confirmation.title == "Free port 5000?")
    }

    @Test("Says the action cannot be undone")
    func warnsThatTheActionIsIrreversible() {
        let confirmation = FreePortMessages.confirmation(port: 3001, targets: [server], leftAlone: [])
        #expect(confirmation.body.contains("cannot be undone"))
    }

    @Test("Reads as singular for one process and plural for several")
    func agreesInNumber() {
        let single = FreePortMessages.confirmation(port: 3001, targets: [server], leftAlone: [])
        let several = FreePortMessages.confirmation(port: 3001, targets: [server, worker], leftAlone: [])
        #expect(single.body.contains("unsaved in that process"))
        #expect(several.body.contains("unsaved in those processes"))
    }

    @Test("Separates processes it will not touch from the ones it will")
    func distinguishesProcessesItWillNotTouch() {
        let confirmation = FreePortMessages.confirmation(port: 3001, targets: [server], leftAlone: [daemon])
        #expect(confirmation.body.contains("Left alone"))
        #expect(confirmation.body.contains("sshd (pid 431)"))
    }

    @Test("Says nothing about untouched processes when there are none")
    func omitsTheUntouchedSectionWhenEmpty() {
        let confirmation = FreePortMessages.confirmation(port: 3001, targets: [server], leftAlone: [])
        #expect(!confirmation.body.contains("Left alone"))
    }

    // MARK: - Outcomes

    @Test("Reports a freed port")
    func reportsFreed() {
        #expect(FreePortMessages.outcome(.freed, port: 3001).title == "Port 3001 is free")
    }

    @Test("Reports that nothing was listening without implying anything was killed")
    func reportsNothingWasListening() {
        let text = FreePortMessages.outcome(.nothingWasListening, port: 3001)
        #expect(text.body.contains("nothing to stop"))
    }

    @Test("Explains an invisible holder rather than calling the port free")
    func reportsAnInvisibleHolder() {
        let text = FreePortMessages.outcome(.heldByAnotherUser(visibleHolders: []), port: 22)
        #expect(text.title.contains("another user"))
        #expect(text.body.contains("Something is listening on port 22"))
    }

    @Test("Names a visible holder it refused to kill")
    func namesARefusedHolder() {
        let text = FreePortMessages.outcome(.heldByAnotherUser(visibleHolders: [daemon]), port: 3001)
        #expect(text.body.contains("sshd (pid 431)"))
        #expect(text.body.contains("nothing was signalled"))
    }

    @Test("Names the survivors when a port stays held")
    func namesSurvivors() {
        let text = FreePortMessages.outcome(.stillHeld(signalled: [server], undelivered: [], untouched: []), port: 3001)
        #expect(text.body.contains("node (pid 26036)"))
        #expect(text.body.contains("SIGKILL"))
    }

    @Test("Names both a wedged survivor and an undelivered one, dropping neither")
    func namesBothKindsOfSurvivor() {
        let text = FreePortMessages.outcome(
            .stillHeld(signalled: [server], undelivered: [worker], untouched: []),
            port: 3001
        )
        #expect(text.body.contains("node (pid 26036)"))
        #expect(text.body.contains("python3 (pid 26037)"))
        #expect(text.body.contains("survived"))
        #expect(text.body.contains("could not deliver"))
    }

    @Test("Says an undelivered signal was never sent, not that it was survived")
    func doesNotCallAnUndeliveredSignalSurvived() {
        let text = FreePortMessages.outcome(
            .stillHeld(signalled: [], undelivered: [server], untouched: []),
            port: 3001
        )
        #expect(text.body.contains("node (pid 26036)"))
        #expect(text.body.contains("never sent anything"))
        #expect(!text.body.contains("survived"))
    }

    @Test("Names an untouched late arrival alongside the survivors")
    func namesUntouchedHoldersToo() {
        let text = FreePortMessages.outcome(
            .stillHeld(signalled: [server], undelivered: [], untouched: [daemon]),
            port: 3001
        )
        #expect(text.body.contains("node (pid 26036)"))
        #expect(text.body.contains("sshd (pid 431)"))
        #expect(text.body.contains("never signalled"))
    }

    @Test("Hedges the cause of an undelivered signal rather than asserting it")
    func doesNotAssertACauseItCannotKnow() {
        let text = FreePortMessages.outcome(
            .stillHeld(signalled: [], undelivered: [server], untouched: []),
            port: 3001
        )
        #expect(text.body.contains("can mean"))
        #expect(!text.body.contains("usually means"))
    }

    @Test("Agrees in number across both survivor lists")
    func stillHeldTextAgreesInNumber() {
        let single = FreePortMessages.outcome(.stillHeld(signalled: [server], undelivered: [worker], untouched: []), port: 3001)
        let several = FreePortMessages.outcome(
            .stillHeld(signalled: [server, worker], undelivered: [server, worker], untouched: []),
            port: 3001
        )
        #expect(single.body.contains("This survived"))
        #expect(single.body.contains("deliver a signal to this one"))
        #expect(several.body.contains("These survived"))
        #expect(several.body.contains("deliver a signal to these"))
    }

    @Test("Never claims a process survived a signal Ward did not send it")
    func doesNotClaimAnUnsignalledProcessSurvived() {
        let text = FreePortMessages.outcome(.takenByAnotherProcess([worker]), port: 3001)
        #expect(text.body.contains("python3 (pid 26037)"))
        #expect(!text.body.contains("SIGKILL"))
        #expect(!text.body.contains("survived"))
        #expect(text.body.contains("did not signal"))
    }

    @Test("Says the kill worked when an invisible process takes the freed port")
    func creditsTheKillWhenThePortIsRetaken() {
        let text = FreePortMessages.outcome(.freedThenTakenByAnotherUser, port: 3001)
        #expect(text.body.contains("Ward stopped what you approved"))
        #expect(text.body.contains("Nothing you approved is still running"))
    }

    @Test("Says a signal already went out when the verifying read fails")
    func reportsAnUnverifiablePortHonestly() {
        let text = FreePortMessages.unverifiablePort(3001)
        #expect(text.body.contains("already signalled"))
        #expect(!text.body.contains("Nothing on this Mac was changed"))
    }

    // MARK: - Refusals

    @Test("Says nothing was changed when the port could not be read")
    func reportsAnUnreadablePort() {
        let text = FreePortMessages.unreadablePort(3001)
        #expect(text.body.contains("nothing was stopped"))
    }

    @Test("Quotes back what was typed when it is not a port")
    func reportsAnUnreadableSpecification() {
        let text = FreePortMessages.unreadablePortSpecification("localhost")
        #expect(text.title.contains("localhost"))
        #expect(text.body.contains("1 and 65535"))
    }
}
