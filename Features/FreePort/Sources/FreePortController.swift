import AppKit
import WardKit

/// Frees a TCP port by stopping whatever is holding it.
///
/// The only destructive feature in Ward, and the only one that is neither
/// fail-open nor fail-closed: a one-shot action that holds no state, so the
/// `WardFeature` defaults are right and there is nothing to recover at launch.
///
/// All of the safety lives before the first signal. `KillEscalation` decides
/// what may be signalled and this type does exactly that and no more — it never
/// widens the set, never retries with more force, and never reaches for `sudo`.
@MainActor
public final class FreePortController: NSObject {
    /// Long enough for a dev server to close its listeners, short enough that
    /// the menu is not left hanging. The port is re-read afterwards, so this is
    /// a grace period rather than an assumption.
    private static let terminationGracePeriod: Duration = .seconds(2)
    /// A killed process releases its sockets as it is reaped, which is not
    /// instantaneous. Without this the verification can read a port as held by
    /// a process that no longer exists.
    private static let forceKillSettlingPeriod: Duration = .milliseconds(300)

    public override init() {
        super.init()
    }

    @objc func freeTypedPortFromMenu() {
        guard let port = promptForPort() else {
            return
        }
        Task {
            await freePort(port)
        }
    }

    @objc func freeListedPortFromMenu(_ sender: NSMenuItem) {
        guard let port = sender.representedObject as? UInt16 else {
            return
        }
        Task {
            await freePort(port)
        }
    }

    func listeningProcesses() -> [ListeningProcess] {
        return PortInspector.allListeningProcesses().sorted { lhs, rhs in
            guard lhs.port == rhs.port else {
                return lhs.port < rhs.port
            }
            return lhs.processIdentifier < rhs.processIdentifier
        }
    }

    func freePort(_ port: UInt16) async {
        guard let snapshot = inspect(port) else {
            return
        }
        let firstStep = KillEscalation.nextStep(
            stage: .initial,
            snapshot: snapshot,
            currentUser: PortInspector.currentUser
        )
        guard case .terminate(let targets) = firstStep else {
            report(firstStep, port: port)
            return
        }
        guard confirmKilling(targets, on: port, among: snapshot.holders) else {
            WardLogger.freePort.notice("Freeing port \(port, privacy: .public) cancelled at the confirmation.")
            return
        }
        await escalate(onPort: port, approvedTargets: Set(targets))
    }

    /// SIGTERM, wait, re-read, SIGKILL the survivors, wait, re-read. Each
    /// re-read is a fresh snapshot: nothing here trusts that a signal worked.
    private func escalate(onPort port: UInt16, approvedTargets: Set<Int32>) async {
        signal(SIGTERM, to: approvedTargets.sorted())
        try? await Task.sleep(for: Self.terminationGracePeriod)

        guard let afterTermination = inspect(port) else {
            return
        }
        let escalationStep = KillEscalation.nextStep(
            stage: .afterTermination(approvedTargets: approvedTargets),
            snapshot: afterTermination,
            currentUser: PortInspector.currentUser
        )
        guard case .forceKill(let survivors) = escalationStep else {
            report(escalationStep, port: port)
            return
        }
        WardLogger.freePort.notice(
            "\(survivors.count, privacy: .public) process(es) survived SIGTERM on port \(port, privacy: .public)."
        )
        signal(SIGKILL, to: survivors)
        try? await Task.sleep(for: Self.forceKillSettlingPeriod)

        guard let afterForceKill = inspect(port) else {
            return
        }
        report(
            KillEscalation.nextStep(
                stage: .afterForceKill(approvedTargets: approvedTargets),
                snapshot: afterForceKill,
                currentUser: PortInspector.currentUser
            ),
            port: port
        )
    }

    private func signal(_ signalNumber: Int32, to processIdentifiers: [Int32]) {
        processIdentifiers.forEach { processIdentifier in
            let outcome = ProcessSignaller.send(signalNumber, to: processIdentifier)
            WardLogger.freePort.info(
                "Signal \(signalNumber, privacy: .public) to pid \(processIdentifier, privacy: .public): \(String(describing: outcome), privacy: .public)"
            )
        }
    }

    /// A failed read is reported rather than treated as an empty port: telling
    /// the user "nothing was listening" when the check never ran would send
    /// them back to try the same thing again.
    private func inspect(_ port: UInt16) -> PortSnapshot? {
        guard let snapshot = PortInspector.snapshot(ofPort: port) else {
            WardLogger.freePort.error("Could not read the state of port \(port, privacy: .public).")
            present(FreePortMessages.unreadablePort(port))
            return nil
        }
        return snapshot
    }

    private func report(_ step: KillEscalation.Step, port: UInt16) {
        guard case .report(let outcome) = step else {
            WardLogger.freePort.fault(
                "Escalation asked for another signal after the final check on port \(port, privacy: .public)."
            )
            return
        }
        WardLogger.freePort.info(
            "Port \(port, privacy: .public): \(String(describing: outcome), privacy: .public)"
        )
        present(FreePortMessages.outcome(outcome, port: port))
    }

    private func confirmKilling(
        _ targets: [Int32],
        on port: UInt16,
        among holders: [ListeningProcess]
    ) -> Bool {
        let approvedTargets = Set(targets)
        let text = FreePortMessages.confirmation(
            port: port,
            targets: holders.filter { approvedTargets.contains($0.processIdentifier) },
            leftAlone: holders.filter { !approvedTargets.contains($0.processIdentifier) }
        )
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = text.title
        alert.informativeText = text.body
        let confirmButton = alert.addButton(withTitle: "Free Port \(port)")
        let cancelButton = alert.addButton(withTitle: "Cancel")
        // Return cancels and Escape cancels. Nothing here can be undone, so the
        // keystroke a user makes without reading must be the harmless one.
        confirmButton.keyEquivalent = ""
        cancelButton.keyEquivalent = "\r"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func promptForPort() -> UInt16? {
        let alert = NSAlert()
        alert.messageText = "Free a Port"
        alert.informativeText = "Which TCP port should Ward free?"
        let portField = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        portField.placeholderString = "3001"
        alert.accessoryView = portField
        alert.addButton(withTitle: "Continue")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = portField
        guard alert.runModal() == .alertFirstButtonReturn else {
            return nil
        }
        let typedSpecification = portField.stringValue
        guard let port = PortSpecParser.parse(typedSpecification) else {
            present(FreePortMessages.unreadablePortSpecification(typedSpecification))
            return nil
        }
        return port
    }

    private func present(_ text: FreePortMessages.AlertText) {
        let alert = NSAlert()
        alert.messageText = text.title
        alert.informativeText = text.body
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
