import AppKit

/// What the app shell needs from a feature.
///
/// Keeps `Sources/Ward` free of any feature's internals: adding a feature means
/// adding a target and one line in the shell, not editing menu-building code.
///
/// The defaults describe a fail-open feature — one whose effects die with the
/// process. A feature that changes state outliving the process must override
/// `isHoldingSystemState` and `recoverLeakedState`, because nothing else will
/// notice what a crash left behind.
@MainActor
public protocol WardFeature: AnyObject {
    /// Rebuilt every time the menu opens, so items reflect live state rather
    /// than what was true when the menu was created.
    func makeMenuItems() -> [NSMenuItem]

    /// True while this feature holds system state that outlives the process.
    /// Drives the quit gate and the menu-bar icon.
    var isHoldingSystemState: Bool { get }

    /// Called once at launch. A feature that changes persistent state must
    /// detect what a crashed previous run left behind and offer to undo it.
    func recoverLeakedState()

    /// Called before the app exits. Return `false` to cancel termination —
    /// used when quitting would strand the system in an altered state.
    func allowsQuit() -> Bool
}

public extension WardFeature {
    var isHoldingSystemState: Bool {
        return false
    }

    func recoverLeakedState() {}

    func allowsQuit() -> Bool {
        return true
    }
}
