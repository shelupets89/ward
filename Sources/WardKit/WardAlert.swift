import AppKit

/// The "this failed, and here is why" dialog, which every feature eventually
/// needs and five of them had each rebuilt by hand.
///
/// Only the single-OK shape lives here. Alerts that ask the user to *choose*
/// — restore or leave it, quit anyway or cancel — carry the decision in their
/// button titles and belong with the feature that has to interpret the answer.
/// Isolated, because `NSAlert` is. Two of the five callers live on types that
/// are not — isolating *those* would reach into the event-tap callbacks behind
/// the esc-hold exit gesture — so each asserts isolation at its own call site
/// instead, where the main-thread reasoning is local and checkable. The other
/// three keep full compile-time checking, which an unisolated helper would have
/// silently given up on their behalf.
@MainActor
public enum WardAlert {
    public static func presentFailure(messageText: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
