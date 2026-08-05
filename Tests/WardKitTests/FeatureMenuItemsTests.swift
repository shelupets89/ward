import AppKit
import Testing
@testable import WardKit

/// `NSMenuItem` construction needs no window server, and this wiring is the one
/// part of the menu that fails silently: a duration that does not round-trip
/// through `representedObject` starts the wrong session, or none at all, with
/// nothing to notice.
@MainActor
struct FeatureMenuItemsTests {
    private final class ActionTarget: NSObject {
        @objc func handle(_ sender: NSMenuItem) {}
    }

    @Test("Points each item at the target that has to receive the action")
    func setsTheTarget() {
        let target = ActionTarget()
        let item = FeatureMenuItems.make(title: "Turn Off", action: #selector(ActionTarget.handle(_:)), target: target)
        #expect(item.target === target)
        #expect(item.title == "Turn Off")
    }

    @Test("Offers every capped duration, in the order they are declared")
    func offersEveryDuration() {
        let target = ActionTarget()
        let submenu = FeatureMenuItems.makeDurationSubmenu(
            title: "Keep Awake",
            action: #selector(ActionTarget.handle(_:)),
            target: target
        ).submenu
        #expect(submenu?.items.map(\.title) == KeepAwakeDuration.allCases.map(\.menuTitle))
    }

    @Test("Round-trips each duration through representedObject")
    func roundTripsDurationsThroughRepresentedObject() {
        let target = ActionTarget()
        let submenu = FeatureMenuItems.makeDurationSubmenu(
            title: "Keep Awake",
            action: #selector(ActionTarget.handle(_:)),
            target: target
        ).submenu
        let carried = submenu?.items.compactMap { $0.representedObject as? KeepAwakeDuration }
        #expect(carried == KeepAwakeDuration.allCases)
    }

    /// AppKit installs its own `submenuAction:` when a submenu is attached, so
    /// the parent is never actionless — what matters is that it does not carry
    /// the feature's action, which would start a session with no duration.
    @Test("Never gives the parent item the action meant for a duration")
    func leavesTheParentInert() {
        let target = ActionTarget()
        let parent = FeatureMenuItems.makeDurationSubmenu(
            title: "Keep Awake",
            action: #selector(ActionTarget.handle(_:)),
            target: target
        )
        #expect(parent.action != #selector(ActionTarget.handle(_:)))
        #expect(parent.representedObject == nil)
    }
}
