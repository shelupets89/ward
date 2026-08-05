import AppKit

/// Menu items wired back to the feature that owns them.
///
/// `target` has to be set explicitly or the action never fires: a status-item
/// menu has no responder chain to fall back on, so an item with a nil target
/// silently does nothing.
public enum FeatureMenuItems {
    public static func make(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        return item
    }

    /// The capped-duration picker both keep-awake features offer. Each leaf
    /// carries its `KeepAwakeDuration` in `representedObject`, so the action
    /// reads the choice back off the sender instead of needing a selector each.
    public static func makeDurationSubmenu(title: String, action: Selector, target: AnyObject) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        KeepAwakeDuration.allCases.forEach { option in
            let optionItem = make(title: option.menuTitle, action: action, target: target)
            optionItem.representedObject = option
            submenu.addItem(optionItem)
        }
        item.submenu = submenu
        return item
    }
}
