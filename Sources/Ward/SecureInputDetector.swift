import AppKit
import Carbon.HIToolbox

/// While another app holds secure keyboard input (a password field), event taps
/// cannot intercept keystrokes — the lock would silently not work, so entry is
/// refused instead.
enum SecureInputDetector {
    static var isSecureInputActive: Bool {
        return IsSecureEventInputEnabled()
    }

    static func presentSecureInputBlockedAlert() {
        let alert = NSAlert()
        alert.messageText = "Another app is capturing secure input"
        alert.informativeText = """
        A password field (or another app using secure keyboard entry) is active, so Ward \
        can’t intercept the keyboard right now. Close the password prompt and try again.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
