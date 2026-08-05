import AppKit

/// The "this failed, and here is why" dialog, which every feature eventually
/// needs and five of them had each rebuilt by hand.
///
/// Only the single-OK shape lives here. Alerts that ask the user to *choose*
/// — restore or leave it, quit anyway or cancel — carry the decision in their
/// button titles and belong with the feature that has to interpret the answer.
/// Deliberately not `@MainActor`, even though `NSAlert` is. Two of the five
/// callers are types that are not main-actor isolated, and isolating them would
/// reach into the event-tap callbacks behind the esc-hold exit gesture. The
/// strict-concurrency warnings this leaves are the ones each hand-rolled copy
/// already produced — now in one place instead of five.
public enum WardAlert {
    public static func presentFailure(messageText: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
