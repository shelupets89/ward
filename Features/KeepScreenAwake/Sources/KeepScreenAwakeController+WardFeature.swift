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
            return [makeDurationSubmenuItem()]
        case .active(let remaining):
            let remainingTime = RemainingTimeFormatting.formatHoursAndMinutes(remaining)
            return [makeItem(title: "Turn Off Keep Screen Awake (\(remainingTime) left)", action: #selector(stopFromMenu))]
        }
    }

    public var isHoldingSystemState: Bool {
        return state != .off
    }

    private func makeDurationSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Keep Screen Awake", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        KeepAwakeDuration.allCases.forEach { option in
            let optionItem = makeItem(title: option.menuTitle, action: #selector(startFromMenu(_:)))
            optionItem.representedObject = option
            submenu.addItem(optionItem)
        }
        item.submenu = submenu
        return item
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
