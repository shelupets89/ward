import AppKit
import WardKit

/// Cleaning Mode fails open — the tap, shields and kiosk options all die with
/// the process — so it needs none of the leak-recovery or quit-gate hooks.
extension CleaningModeController: WardFeature {
    public func makeMenuItems() -> [NSMenuItem] {
        let item = NSMenuItem(
            title: "Start Cleaning Mode",
            action: #selector(startFromMenu),
            keyEquivalent: ""
        )
        item.target = self
        return [item]
    }
}
