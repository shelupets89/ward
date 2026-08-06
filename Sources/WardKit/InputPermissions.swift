import AppKit
import ApplicationServices

/// Accessibility (and, on some macOS versions, Input Monitoring) gate for the
/// active event tap. The shield is never shown unless blocking actually works.
public enum InputPermissions {
    private static let accessibilitySettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    private static let inputMonitoringSettingsURLString =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent"

    public static func ensureAccessibilityGranted() -> Bool {
        if AXIsProcessTrusted() {
            return true
        }
        promptSystemAccessibilityDialog()
        presentSettingsAlert(
            messageText: "Ward needs Accessibility access",
            informativeText: InputPermissionAlertBody.describeMissingAccessibility(
                runningBundlePath: runningBundlePath
            ),
            settingsButtonTitle: "Open Accessibility Settings",
            settingsURLString: accessibilitySettingsURLString
        )
        return false
    }

    /// Accessibility is granted but the tap was still refused, which on recent
    /// macOS versions means Input Monitoring is the missing grant.
    public static func presentTapCreationFailedAlert() {
        CGRequestListenEventAccess()
        presentSettingsAlert(
            messageText: "Ward can’t lock input yet",
            informativeText: InputPermissionAlertBody.describeRefusedInputTap(
                runningBundlePath: runningBundlePath
            ),
            settingsButtonTitle: "Open Input Monitoring Settings",
            settingsURLString: inputMonitoringSettingsURLString
        )
    }

    private static var runningBundlePath: String {
        return Bundle.main.bundleURL.path
    }

    private static func promptSystemAccessibilityDialog() {
        let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        let options = [promptKey: true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    private static func presentSettingsAlert(
        messageText: String,
        informativeText: String,
        settingsButtonTitle: String,
        settingsURLString: String
    ) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: settingsButtonTitle)
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else {
            return
        }
        guard let settingsURL = URL(string: settingsURLString) else {
            return
        }
        NSWorkspace.shared.open(settingsURL)
    }
}
