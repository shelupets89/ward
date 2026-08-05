import AppKit
import WardKit

/// A one-shot action, so every `WardFeature` hook keeps its default: nothing is
/// held while the app runs, nothing survives it, and nothing needs recovering
/// at launch. Only the menu is implemented.
///
/// Two entries rather than one. Typing a port is the case the user came for and
/// stays one click away; the listing is the shortcut for when they know the
/// port is taken but not by what.
extension FreePortController: WardFeature {
    public func makeMenuItems() -> [NSMenuItem] {
        return [makeItem(title: "Free a Port…", action: #selector(freeTypedPortFromMenu)), makePortListItem()]
    }

    /// Populated on demand: a full `lsof` takes around 200ms, which is a stall
    /// the user should only pay when they actually ask to see the list.
    private func makePortListItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Ports in Use", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        submenu.delegate = self
        item.submenu = submenu
        return item
    }

    private func makeItem(title: String, action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        return item
    }
}

extension FreePortController: NSMenuDelegate {
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let listeners = listeningProcesses()
        guard !listeners.isEmpty else {
            let emptyItem = NSMenuItem(title: "Nothing is listening", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            return
        }
        listeners.forEach { listener in
            let item = makeItem(
                title: "\(listener.port) — \(listener.displayName)",
                action: #selector(freeListedPortFromMenu(_:))
            )
            item.representedObject = listener.port
            menu.addItem(item)
        }
    }
}
