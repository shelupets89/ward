import AppKit

/// What the app shell needs from a feature.
///
/// Keeps `Sources/Ward` free of any feature's internals: adding a feature means
/// adding a target and one line in the shell, not editing menu-building code.
///
/// The defaults describe a fail-open feature — one whose effects die with the
/// process. Such a feature may still override `isHoldingSystemState` to raise
/// the bolt while it is doing something, and that alone changes nothing about
/// its failure model. A feature whose effects outlive the process must go
/// further and override `recoverLeakedState` and `allowsQuit`, because after a
/// crash nothing is left running to notice what it left behind.
@MainActor
public protocol WardFeature: AnyObject {
    /// Rebuilt every time the menu opens, so items reflect live state rather
    /// than what was true when the menu was created.
    func makeMenuItems() -> [NSMenuItem]

    /// True while this feature is altering the Mac right now. Raises the
    /// menu-bar bolt, so it covers effects that die with the process (a power
    /// assertion) as well as ones that outlive it. Cancelling a quit is
    /// `allowsQuit()`'s job, not this one's.
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
