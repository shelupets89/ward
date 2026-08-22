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
    private static let accessibilitySettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private static let inputMonitoringSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    public static func ensureAccessibilityGranted() -> Bool {
        // `AXIsProcessTrusted` is the preflight — the check that never shows a
        // dialog. The prompting variant lives in the hand-off below, where the
        // user has already asked for it.
        guard PermissionEscalation.nextSteps(
            .notYetAsked(isAlreadyGranted: AXIsProcessTrusted())
        ) == [.explain] else {
            return true
        }
        escalate(
            messageText: "Ward needs Accessibility access",
            informativeText: InputPermissionAlertBody.describeMissingAccessibility(
                runningBundlePath: runningBundlePath
            ),
            settingsButtonTitle: "Open Accessibility Settings",
            settingsURLString: accessibilitySettingsURLString,
            registerWithSystem: {
                // Written out here rather than behind a name of its own. A named
                // `promptSystemAccessibilityDialog()` is what made calling it too
                // early a single line to type, and that is the call this whole
                // arrangement exists to keep behind the explanation.
                let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
                AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
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
            settingsButtonTitle: "Open Input Monitoring Settings",
            settingsURLString: inputMonitoringSettingsURLString,
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
        settingsButtonTitle: String,
        settingsURLString: String,
        registerWithSystem: () -> Void
    ) {
        let userChoseSettings = askUser(
            messageText: messageText,
            informativeText: informativeText,
            settingsButtonTitle: settingsButtonTitle
        )
        for step in PermissionEscalation.nextSteps(.explained(userChoseSettings: userChoseSettings)) {
            switch step {
            case .explain:
                // Unreachable from `.explained` — the explanation is what got us
                // here. Handled rather than defaulted so that a new step added
                // to `Step` is a compile error here, not a silent no-op.
                break
            case .registerWithSystem:
                registerWithSystem()
            case .openSettingsPane:
                openSettingsPane(settingsURLString)
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
