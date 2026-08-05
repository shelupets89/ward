import AppKit
import WardKit

/// Keep Screen Awake fails open, so it takes the protocol defaults for the
/// launch leak check and the quit gate: there is nothing a crash could strand
/// and nothing quitting could leave behind.
///
/// `isHoldingSystemState` is the exception. It raises the menu-bar bolt, which
/// answers "is this Mac currently altered?" — and a live display assertion is
/// exactly that, whether or not it outlives the process.
extension KeepScreenAwakeController: WardFeature {
    public func makeMenuItems() -> [NSMenuItem] {
        endSessionIfExpired()
        switch state {
        case .off:
            return [
                FeatureMenuItems.makeDurationSubmenu(
                    title: "Keep Screen Awake",
                    action: #selector(startFromMenu(_:)),
                    target: self
                )
            ]
        case .active(let remaining):
            let remainingTime = RemainingTimeFormatting.formatHoursAndMinutes(remaining)
            return [
                FeatureMenuItems.make(
                    title: "Turn Off Keep Screen Awake (\(remainingTime) left)",
                    action: #selector(stopFromMenu),
                    target: self
                )
            ]
        case .overrunning:
            return [
                FeatureMenuItems.make(
                    title: "Turn Off Keep Screen Awake (macOS won’t release it)",
                    action: #selector(stopFromMenu),
                    target: self
                )
            ]
        }
    }

    public var isHoldingSystemState: Bool {
        return state != .off
    }
}
