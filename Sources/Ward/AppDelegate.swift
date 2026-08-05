import AppKit
import CleaningMode
import KeepAwakeLidClosed
import WardKit

/// Owns the status item and nothing else. Every menu entry above Quit comes
/// from a feature — this file has no knowledge of what any of them do, so
/// adding a feature means adding one line to `features`.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let features: [any WardFeature] = [
        CleaningModeController(),
        KeepAwakeController()
    ]
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        features.forEach { feature in
            feature.recoverLeakedState()
        }
        refreshStatusItemIcon()
    }

    /// Asks every feature in turn. A feature that would strand the system in an
    /// altered state gets to cancel the quit and explain why.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let doesEveryFeatureAllowQuit = features.allSatisfy { feature in
            feature.allowsQuit()
        }
        return doesEveryFeatureAllowQuit ? .terminateNow : .terminateCancel
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatusItemIcon()
    }

    /// The bolt means "this Mac is currently altered", not "Ward is busy" — any
    /// feature holding system state raises it.
    private func refreshStatusItemIcon() {
        guard let button = statusItem?.button else {
            return
        }
        let isSystemAltered = features.contains { feature in
            feature.isHoldingSystemState
        }
        let symbolName = isSystemAltered ? "bolt.fill" : "bubbles.and.sparkles"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Ward")
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Ward")
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        features.forEach { feature in
            feature.makeMenuItems().forEach { item in
                menu.addItem(item)
            }
            menu.addItem(.separator())
        }
        menu.addItem(
            NSMenuItem(
                title: "Quit Ward",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt on every open so features report live state rather than whatever
    /// was true when the menu was created.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
        refreshStatusItemIcon()
    }
}
