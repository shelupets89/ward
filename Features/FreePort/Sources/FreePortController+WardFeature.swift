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
        return FeatureMenuItems.make(title: title, action: action, target: self)
    }
}

extension FreePortController: NSMenuDelegate {
    /// Fills the submenu after the fact rather than blocking here. `lsof` goes
    /// through `BoundedProcess`, which blocks its thread for up to ten seconds —
    /// on the main thread that is the whole app frozen, and this menu is opened
    /// out of curiosity. The placeholder is replaced in place once the read
    /// returns; an `NSMenu` accepts items while it is open.
    public func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(makeDisabledItem(titled: "Reading…"))
        Task {
            fill(menu, with: await listeningProcesses())
        }
    }

    private func fill(_ menu: NSMenu, with listeners: [ListeningProcess]?) {
        menu.removeAllItems()
        guard let listeners else {
            menu.addItem(makeDisabledItem(titled: "Couldn’t read the port list"))
            return
        }
        guard !listeners.isEmpty else {
            menu.addItem(makeDisabledItem(titled: "Nothing is listening"))
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

    private func makeDisabledItem(titled title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }
}
