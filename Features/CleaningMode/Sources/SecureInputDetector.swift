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

    /// Isolated rather than asserting isolation internally: this is `internal`
    /// on an `enum`, so anything in the module can call it. Declaring the
    /// requirement makes a wrong caller a compile error instead of a trap, and
    /// leaves the assertion to `enterCleaningMode`, where the main-thread
    /// reasoning is local and checkable.
    @MainActor
    static func presentSecureInputBlockedAlert() {
        WardAlert.presentFailure(
            messageText: "Another app is capturing secure input",
            informativeText: """
            A password field (or another app using secure keyboard entry) is active, so Ward \
            can’t intercept the keyboard right now. Close the password prompt and try again.
            """
        )
    }
}
