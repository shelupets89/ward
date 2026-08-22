import AppKit
import ApplicationServices

/// Accessibility (and, on some macOS versions, Input Monitoring) gate for the
/// active event tap. The shield is never shown unless blocking actually works.
///
/// Isolated, because `NSAlert` is — the same reason `WardAlert` is. Both callers
/// are already on the main actor, so declaring it here costs nothing and stops
/// the chain relying on that happening to stay true.
///
/// Nothing in this type decides what order anything happens in. It asks
/// `PermissionEscalation` and runs what it is handed, which is why the system
/// prompt can no longer arrive before the alert that explains it.
@MainActor
public enum InputPermissions {
    public static func ensureAccessibilityGranted() -> Bool {
        // `AXIsProcessTrusted` is the preflight — the check that never shows a
        // dialog. The prompting variant lives in the hand-off below, where the
        // user has already asked for it.
        let opening = PermissionEscalation.nextSteps(
            .notYetAsked(isAlreadyGranted: AXIsProcessTrusted())
        )
        if opening.isEmpty {
            return true
        }
        // Anything other than "explain" is a shape this does not recognise, and
        // the safe reading of it is not "granted". An earlier version compared
        // for equality and fell through to `return true`, which made an
        // unrecognised escalation indistinguishable from a granted one — the
        // optimistic branch, where `FreePortController` fails loud instead.
        guard opening == [.explain] else {
            WardLogger.inputBlocking.fault(
                "Escalation asked for something other than an explanation before anything was shown."
            )
            return false
        }
        escalate(
            messageText: "Ward needs Accessibility access",
            informativeText: InputPermissionAlertBody.describeMissingAccessibility(
                runningBundlePath: runningBundlePath
            ),
            grant: .accessibility,
            registerWithSystem: {
                // Written out here rather than behind a name of its own. A named
                // `promptSystemAccessibilityDialog()` is what made calling it too
                // early a single line to type, and that is the call this whole
                // arrangement exists to keep behind the explanation.
                let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                _ = AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
            }
        )
        return false
    }

    /// Accessibility is granted but the tap was still refused, which on recent
    /// macOS versions means Input Monitoring is the missing grant.
    ///
    /// There is no preflight here, so the alert always shows: this is only
    /// reached once the tap has already failed, which is a stronger signal than
    /// `CGPreflightListenEventAccess` would give.
    public static func presentTapCreationFailedAlert() {
        escalate(
            messageText: "Ward can’t lock input yet",
            informativeText: InputPermissionAlertBody.describeRefusedInputTap(
                runningBundlePath: runningBundlePath
            ),
            grant: .inputMonitoring,
            registerWithSystem: {
                // The SDK is explicit that this prompts: "Requests event
                // listening access if absent, potentially prompting"
                // (CGEvent.h). Same stacking bug as Accessibility had, so the
                // same fix, rather than the two flows drifting apart.
                _ = CGRequestListenEventAccess()
            }
        )
    }

    private static var runningBundlePath: String {
        return Bundle.main.bundleURL.path
    }

    /// Explains, then does whatever follows from the answer — in the order it is
    /// given them, deciding none of it.
    private static func escalate(
        messageText: String,
        informativeText: String,
        grant: PermissionEscalation.Grant,
        registerWithSystem: () -> Void
    ) {
        let userChoseSettings = askUser(
            messageText: messageText,
            informativeText: informativeText,
            settingsButtonTitle: grant.settingsButtonTitle
        )
        for step in PermissionEscalation.nextSteps(.explained(userChoseSettings: userChoseSettings)) {
            switch step {
            case .explain:
                // Unreachable from `.explained` — the explanation is what got us
                // here. Naming the case rather than writing `default` is what
                // makes a step added to `Step` a compile error at this switch;
                // that much the compiler enforces. Reaching *this* arm would
                // mean the escalation changed under us, so it says so rather
                // than falling through silently, which is what the same
                // situation gets in `FreePortController.report`.
                WardLogger.inputBlocking.fault(
                    "Escalation asked for an explanation after one had already been shown."
                )
            case .registerWithSystem:
                registerWithSystem()
            case .openSettingsPane:
                openSettingsPane(grant.settingsURLString)
            }
        }
    }

    /// Returns whether the user asked to be taken to Settings.
    private static func askUser(
        messageText: String,
        informativeText: String,
        settingsButtonTitle: String
    ) -> Bool {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: settingsButtonTitle)
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private static func openSettingsPane(_ settingsURLString: String) {
        guard let settingsURL = URL(string: settingsURLString) else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }
}
