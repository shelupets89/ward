import AppKit
import Carbon.HIToolbox
import WardKit

/// While another app holds secure keyboard input (a password field), event taps
/// cannot intercept keystrokes — the lock would silently not work, so entry is
/// refused instead.
enum SecureInputDetector {
    static var isSecureInputActive: Bool {
        return IsSecureEventInputEnabled()
    }

    /// Asserted rather than isolated, for the same reason as
    /// `CleaningModeController.presentShieldFailureAlert`: the only caller is
    /// `enterCleaningMode`, reached from an `@objc` menu action.
    static func presentSecureInputBlockedAlert() {
        MainActor.assumeIsolated {
            WardAlert.presentFailure(
                messageText: "Another app is capturing secure input",
                informativeText: """
                A password field (or another app using secure keyboard entry) is active, so Ward \
                can’t intercept the keyboard right now. Close the password prompt and try again.
                """
            )
        }
    }
}
