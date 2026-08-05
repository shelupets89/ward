import AppKit
import WardCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let cleaningModeController = CleaningModeController()
    private let keepAwakeController = KeepAwakeController()
    private var statusItem: NSStatusItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureStatusItem()
        keepAwakeController.offerToRestoreUnownedSetting()
        refreshStatusItemIcon()
    }

    /// Quitting with keep-awake still on would leave the Mac unable to sleep on
    /// lid close with nothing left running to undo it, so quit is gated here
    /// rather than silently restoring during termination.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard keepAwakeController.isHoldingSleepDisabled else {
            return .terminateNow
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
            guard keepAwakeController.stop(allowInteractivePrompt: true) else {
                presentRestoreFailedBeforeQuitAlert()
                return .terminateCancel
            }
            return .terminateNow
        case .alertSecondButtonReturn:
            WardLogger.keepAwake.notice("Quit with lid sleep left disabled.")
            return .terminateNow
        default:
            return .terminateCancel
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleaningModeController.exitCleaningMode()
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
        refreshStatusItemIcon()
    }

    /// The bolt also covers the unowned case: the icon reports whether this Mac
    /// can sleep, not whether Ward is the one holding it awake.
    private func refreshStatusItemIcon() {
        guard let button = statusItem?.button else {
            return
        }
        let isSleepHeldOff = keepAwakeController.menuState != .off
        let symbolName = isSleepHeldOff ? "bolt.fill" : "bubbles.and.sparkles"
        button.image = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Ward")
            ?? NSImage(systemSymbolName: "sparkles", accessibilityDescription: "Ward")
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()
        menu.addItem(makeItem(title: "Start Cleaning Mode", action: #selector(startCleaningMode)))
        menu.addItem(.separator())
        menu.addItem(makeKeepAwakeItem())
        if keepAwakeController.needsPasswordlessSetup {
            menu.addItem(
                makeItem(title: "Set Up Touch ID for Keep Awake…", action: #selector(setUpPasswordlessToggle))
            )
        }
        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Ward",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"
            )
        )
    }

    private func makeKeepAwakeItem() -> NSMenuItem {
        switch keepAwakeController.menuState {
        case .off:
            return makeDurationSubmenuItem()
        case .awaitingConfirmation:
            let item = NSMenuItem(title: "Waiting for confirmation…", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return item
        case .active(let remainingTime):
            return makeItem(
                title: "Turn Off Keep Awake (\(remainingTime) left)",
                action: #selector(stopKeepAwake)
            )
        case .unownedAndDisabled:
            return makeItem(
                title: "Restore Normal Sleep (lid sleep is disabled)",
                action: #selector(restoreUnownedSetting)
            )
        }
    }

    private func makeDurationSubmenuItem() -> NSMenuItem {
        let item = NSMenuItem(title: "Keep Awake with Lid Closed", action: nil, keyEquivalent: "")
        let submenu = NSMenu()
        KeepAwakeDuration.allCases.forEach { option in
            let optionItem = makeItem(title: option.menuTitle, action: #selector(startKeepAwake(_:)))
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

    private func presentRestoreFailedBeforeQuitAlert() {
        let alert = NSAlert()
        alert.messageText = "Ward stayed open — sleep is still disabled"
        alert.informativeText = """
        Restoring normal sleep needs administrator rights, and the authorization was declined or \
        failed, so Ward did not quit. Try again, or choose Quit Anyway to leave the setting in place.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    @objc private func startCleaningMode() {
        cleaningModeController.enterCleaningMode()
    }

    @objc private func startKeepAwake(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? KeepAwakeDuration else {
            return
        }
        Task {
            await keepAwakeController.start(for: option)
            refreshStatusItemIcon()
        }
    }

    @objc private func stopKeepAwake() {
        guard keepAwakeController.stop(allowInteractivePrompt: true) else {
            presentRestoreFailedBeforeQuitAlert()
            refreshStatusItemIcon()
            return
        }
        refreshStatusItemIcon()
    }

    @objc private func setUpPasswordlessToggle() {
        keepAwakeController.setUpPasswordlessToggle()
    }

    @objc private func restoreUnownedSetting() {
        keepAwakeController.offerToRestoreUnownedSetting()
        refreshStatusItemIcon()
    }
}

extension AppDelegate: NSMenuDelegate {
    /// Rebuilt on every open so the remaining-time readout and the on/off state
    /// are current — including a setting left behind by a previous run, which is
    /// re-read from the system here rather than assumed.
    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
        refreshStatusItemIcon()
    }
}
