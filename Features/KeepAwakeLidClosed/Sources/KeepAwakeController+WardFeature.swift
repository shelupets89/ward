import AppKit
import WardKit

/// Keep Awake fails closed — `pmset disablesleep` outlives the process — so it
/// implements every hook: the launch leak check, the quit gate, and the icon
/// signal that this Mac currently cannot sleep.
extension KeepAwakeController: WardFeature {
    public func makeMenuItems() -> [NSMenuItem] {
        switch menuState {
        case .off:
            return [makeDurationSubmenuItem()] + makePasswordlessSetupItemIfNeeded()
        case .awaitingConfirmation:
            let item = NSMenuItem(title: "Waiting for confirmation…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return [item]
        case .active(let remainingTime):
            return [makeItem(title: "Turn Off Keep Awake (\(remainingTime) left)", action: #selector(stopFromMenu))]
        case .unownedAndDisabled:
            return [makeItem(title: "Restore Normal Sleep (lid sleep is disabled)", action: #selector(restoreFromMenu))]
        }
    }

    public var isHoldingSystemState: Bool {
        return menuState != .off
    }

    public func recoverLeakedState() {
        offerToRestoreUnownedSetting()
    }

    public func allowsQuit() -> Bool {
        guard isHoldingSleepDisabled else {
            return true
        }
        let alert = NSAlert()
        alert.messageText = "Keep Awake is still on"
        alert.informativeText = """
        This Mac is set to stay awake with the lid closed, and that setting outlives Ward. \
        Quitting without restoring means it stays disabled until you turn it back on manually.
        """
        alert.addButton(withTitle: "Restore Sleep and Quit")
        alert.addButton(withTitle: "Quit Anyway")
        alert.addButton(withTitle: "Cancel")
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            return stop(allowInteractivePrompt: true)
        case .alertSecondButtonReturn:
            WardLogger.keepAwake.notice("Quit with lid sleep left disabled.")
            return true
        default:
            return false
        }
    }

    private func makeDurationSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Keep Awake with Lid Closed", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        KeepAwakeDuration.allCases.forEach { option in
            let optionItem = makeItem(title: option.menuTitle, action: #selector(startFromMenu(_:)))
            optionItem.representedObject = option
            submenu.addItem(optionItem)
        }
        item.submenu = submenu
        return item
    }

    private func makePasswordlessSetupItemIfNeeded() -> [NSMenuItem] {
        guard needsPasswordlessSetup else {
            return []
        }
        return [makeItem(title: "Set Up Touch ID for Keep Awake…", action: #selector(setUpPasswordlessFromMenu))]
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}
