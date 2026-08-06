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

    /// The menu stays open during the grace period, so the same port can be
    /// asked for twice. A second run would stack a second confirmation over the
    /// first and report a contradictory outcome for one port.
    private var portsBeingFreed: Set<UInt16> = []

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

    /// `nil` when `lsof` could not be read — distinct from an empty list, which
    /// means nothing is listening. Runs off the main actor: `BoundedProcess`
    /// blocks its thread for up to ten seconds, and this is reached from a menu
    /// the user merely opened.
    func listeningProcesses() async -> [ListeningProcess]? {
        let listeners = await Task.detached {
            return PortInspector.allListeningProcesses()
        }.value
        return listeners?.sorted { lhs, rhs in
            guard lhs.port == rhs.port else {
                return lhs.port < rhs.port
            }
            return lhs.processIdentifier < rhs.processIdentifier
        }
    }

    func freePort(_ port: UInt16) async {
        guard portsBeingFreed.insert(port).inserted else {
            WardLogger.freePort.notice("Already freeing port \(port, privacy: .public); ignoring the repeat.")
            return
        }
        defer { portsBeingFreed.remove(port) }
        guard let snapshot = await inspect(port) else {
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
        // Discarded deliberately: only the SIGKILL round's result describes the
        // final state, and anything refused here is re-signalled below anyway.
        _ = signal(.terminate, to: approvedTargets.sorted())
        guard await waited(Self.terminationGracePeriod, onPort: port) else {
            present(FreePortMessages.unverifiablePort(port))
            return
        }
        guard let afterTermination = await inspect(port, afterSignalling: true) else {
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
        // "Still present", not "survived": SIGTERM may have been refused rather
        // than ignored, and the log should not assert a delivery either.
        WardLogger.freePort.notice(
            "\(survivors.count, privacy: .public) process(es) still on port \(port, privacy: .public) after SIGTERM."
        )
        // The SIGKILL round's result is the only one that describes the final
        // state. A pid macOS refused at SIGTERM but accepted here *was*
        // signalled, and carrying the earlier refusal forward would report it
        // as never touched.
        let undeliveredForceKill = signal(.forceKill, to: survivors)
        guard await waited(Self.forceKillSettlingPeriod, onPort: port) else {
            present(FreePortMessages.unverifiablePort(port))
            return
        }
        guard let afterForceKill = await inspect(port, afterSignalling: true) else {
            return
        }
        report(
            KillEscalation.nextStep(
                stage: .afterForceKill(
                    approvedTargets: approvedTargets,
                    undeliveredTargets: undeliveredForceKill
                ),
                snapshot: afterForceKill,
                currentUser: PortInspector.currentUser
            ),
            port: port
        )
    }

    /// Returns the pids the signal never reached — refused by macOS, or failed
    /// outright. Both belong in one set because the report turns on delivery,
    /// not on the reason: an undelivered signal leaves the process running, and
    /// calling that "survived SIGKILL" describes something that never happened
    /// and sends the user looking for a fix that does not exist.
    private func signal(_ signal: ProcessSignaller.Signal, to processIdentifiers: [Int32]) -> Set<Int32> {
        let outcomes = processIdentifiers.map { processIdentifier in
            let outcome = ProcessSignaller.send(signal, to: processIdentifier)
            WardLogger.freePort.info(
                "\(String(describing: signal), privacy: .public) to pid \(processIdentifier, privacy: .public): \(String(describing: outcome), privacy: .public)"
            )
            return (processIdentifier, outcome)
        }
        return Set(outcomes.filter { $0.1 == .notPermitted || $0.1 == .failed }.map(\.0))
    }

    /// False if the wait was cut short. A grace period that did not actually
    /// elapse must not be mistaken for one that did — that would read a process
    /// still shutting down cleanly as a survivor and escalate to SIGKILL.
    private func waited(_ period: Duration, onPort port: UInt16) async -> Bool {
        do {
            try await Task.sleep(for: period)
            return true
        } catch {
            WardLogger.freePort.notice("Wait on port \(port, privacy: .public) was cancelled; not escalating.")
            return false
        }
    }

    /// A failed read is reported rather than treated as an empty port: telling
    /// the user "nothing was listening" when the check never ran would send
    /// them back to try the same thing again.
    ///
    /// `afterSignalling` picks the honest wording. Once signals have gone out,
    /// "nothing was changed" is no longer something Ward can claim.
    private func inspect(_ port: UInt16, afterSignalling: Bool = false) async -> PortSnapshot? {
        let snapshot = await Task.detached {
            return PortInspector.snapshot(ofPort: port)
        }.value
        guard let snapshot else {
            WardLogger.freePort.error("Could not read the state of port \(port, privacy: .public).")
            present(afterSignalling
                ? FreePortMessages.unverifiablePort(port)
                : FreePortMessages.unreadablePort(port))
            return nil
        }
        return snapshot
    }

    private func report(_ step: KillEscalation.Step, port: UInt16) {
        guard case .report(let outcome) = step else {
            WardLogger.freePort.fault(
                "Escalation asked for another signal after the final check on port \(port, privacy: .public)."
            )
            present(FreePortMessages.unverifiablePort(port))
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
        alert.addButton(withTitle: "Cancel")
        // Clearing the default Return binding leaves the destructive button
        // reachable only by an actual click, and leaves Cancel with the Escape
        // key AppKit gives it by title. Nothing here can be undone, so no
        // keystroke made without reading should confirm it.
        confirmButton.keyEquivalent = ""
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
        WardAlert.presentFailure(messageText: text.title, informativeText: text.body)
    }
}
