import AppKit
import WardCore

/// Orchestrates entering and leaving cleaning mode: permission gates, the
/// event tap, shield windows, kiosk options, and the esc-hold exit gesture.
final class CleaningModeController {
    private static let requiredHoldSeconds = 5
    private static let progressUpdateInterval: TimeInterval = 1.0 / 30.0
    private static let secureInputCheckInterval: TimeInterval = 1
    private static let kioskPresentationOptions: NSApplication.PresentationOptions = [
        .hideDock,
        .hideMenuBar,
        .disableAppleMenu,
        .disableProcessSwitching,
        .disableForceQuit,
        .disableSessionTermination,
        .disableHideApplication
    ]

    private let overlayModel = ShieldOverlayModel(
        requiredHoldSeconds: CleaningModeController.requiredHoldSeconds
    )
    private let displaySleepPreventer = DisplaySleepPreventer()
    private var holdTracker = EscapeHoldTracker(
        requiredHoldDuration: .seconds(CleaningModeController.requiredHoldSeconds)
    )
    private var inputBlocker: InputBlocker?
    private var backupKeyboardMonitor: BackupKeyboardMonitor?
    private var shieldWindowsController: ShieldWindowsController?
    private var progressTimer: Timer?
    private var secureInputWatchdogTimer: Timer?
    private(set) var isActive = false

    func enterCleaningMode() {
        guard !isActive else {
            return
        }
        guard InputPermissions.ensureAccessibilityGranted() else {
            return
        }
        guard !SecureInputDetector.isSecureInputActive else {
            WardLogger.cleaningMode.notice("Entry refused: another app holds secure keyboard input.")
            SecureInputDetector.presentSecureInputBlockedAlert()
            return
        }
        let handlers = makeInputEventHandlers()
        let blocker = InputBlocker(handlers: handlers)
        guard blocker.start() else {
            InputPermissions.presentTapCreationFailedAlert()
            return
        }
        let windowsController = ShieldWindowsController(overlayModel: overlayModel)
        guard windowsController.showShields() else {
            WardLogger.cleaningMode.error("No screens available to shield; aborting entry.")
            blocker.stop()
            presentShieldFailureAlert()
            return
        }
        inputBlocker = blocker
        shieldWindowsController = windowsController
        isActive = true
        holdTracker.reset()
        holdTracker.updateModifiersDown(WatchedModifiers.areDown(in: NSEvent.modifierFlags))
        overlayModel.reset()
        activateApp()
        NSApp.presentationOptions = Self.kioskPresentationOptions
        NSCursor.hide()
        if !displaySleepPreventer.beginPreventingDisplaySleep() {
            WardLogger.cleaningMode.warning("Display sleep assertion failed; screen may sleep mid-session.")
        }
        let monitor = BackupKeyboardMonitor(handlers: handlers)
        if monitor.start() {
            backupKeyboardMonitor = monitor
        } else {
            WardLogger.cleaningMode.warning("Backup keyboard monitor failed to install; tap is the only exit path.")
        }
        startSecureInputWatchdog()
        observeScreenParameterChanges()
        WardLogger.cleaningMode.info("Cleaning mode active.")
    }

    func exitCleaningMode() {
        guard isActive else {
            return
        }
        isActive = false
        stopProgressTimer()
        stopSecureInputWatchdog()
        stopObservingScreenParameterChanges()
        backupKeyboardMonitor?.stop()
        backupKeyboardMonitor = nil
        inputBlocker?.stop()
        inputBlocker = nil
        displaySleepPreventer.endPreventingDisplaySleep()
        NSCursor.unhide()
        shieldWindowsController?.closeShields()
        shieldWindowsController = nil
        NSApp.presentationOptions = []
        holdTracker.reset()
        overlayModel.reset()
        WardLogger.cleaningMode.info("Cleaning mode exited.")
    }

    private func makeInputEventHandlers() -> InputEventHandlers {
        return InputEventHandlers(
            onEscapeKeyDown: { [weak self] in
                self?.handleEscapeKeyDown()
            },
            onEscapeKeyUp: { [weak self] in
                self?.handleEscapeKeyUp()
            },
            onOtherKeyDown: { [weak self] in
                self?.handleOtherKeyDown()
            },
            onModifiersChanged: { [weak self] areModifiersDown in
                self?.handleModifiersChanged(areModifiersDown)
            },
            onIrrecoverableFailure: { [weak self] in
                self?.exitCleaningMode()
            }
        )
    }

    private func handleEscapeKeyDown() {
        guard isActive else {
            return
        }
        holdTracker.registerEscapeKeyDown(at: ContinuousClock.now)
        synchronizeOverlayWithTracker()
    }

    private func handleEscapeKeyUp() {
        guard isActive else {
            return
        }
        holdTracker.registerEscapeKeyUp()
        synchronizeOverlayWithTracker()
    }

    private func handleOtherKeyDown() {
        guard isActive else {
            return
        }
        holdTracker.registerOtherKeyDown()
        synchronizeOverlayWithTracker()
    }

    private func handleModifiersChanged(_ areModifiersDown: Bool) {
        guard isActive else {
            return
        }
        holdTracker.updateModifiersDown(areModifiersDown)
        synchronizeOverlayWithTracker()
    }

    private func synchronizeOverlayWithTracker() {
        if holdTracker.isHolding {
            overlayModel.showHoldProgress(holdTracker.progress(at: ContinuousClock.now))
            startProgressTimerIfNeeded()
        } else {
            stopProgressTimer()
            overlayModel.reset()
        }
    }

    private func startProgressTimerIfNeeded() {
        guard progressTimer == nil else {
            return
        }
        let timer = Timer(timeInterval: Self.progressUpdateInterval, repeats: true) { [weak self] _ in
            self?.handleProgressTick()
        }
        RunLoop.main.add(timer, forMode: .common)
        progressTimer = timer
    }

    private func handleProgressTick() {
        let now = ContinuousClock.now
        if holdTracker.isComplete(at: now) {
            exitCleaningMode()
        } else {
            overlayModel.showHoldProgress(holdTracker.progress(at: now))
        }
    }

    private func stopProgressTimer() {
        progressTimer?.invalidate()
        progressTimer = nil
    }

    /// Secure input can engage after entry (a background password prompt), and
    /// it stops the tap from seeing the very esc presses needed to get out —
    /// so the only safe response is to leave while leaving is still possible.
    private func startSecureInputWatchdog() {
        let timer = Timer(timeInterval: Self.secureInputCheckInterval, repeats: true) { [weak self] _ in
            guard SecureInputDetector.isSecureInputActive else {
                return
            }
            WardLogger.cleaningMode.error("Secure input engaged mid-session; exiting to avoid a trapped session.")
            self?.exitCleaningMode()
        }
        RunLoop.main.add(timer, forMode: .common)
        secureInputWatchdogTimer = timer
    }

    private func stopSecureInputWatchdog() {
        secureInputWatchdogTimer?.invalidate()
        secureInputWatchdogTimer = nil
    }

    private func presentShieldFailureAlert() {
        let alert = NSAlert()
        alert.messageText = "Ward can’t cover the screen"
        alert.informativeText = """
        macOS reported no available displays, so cleaning mode was not started. Try again in a moment.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func activateApp() {
        // The parameterless activate() supersedes activate(ignoringOtherApps:)
        // in macOS 14; the package still supports macOS 13.
        if #available(macOS 14.0, *) {
            NSApp.activate()
        } else {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func observeScreenParameterChanges() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    private func stopObservingScreenParameterChanges() {
        NotificationCenter.default.removeObserver(
            self,
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
    }

    @objc private func handleScreenParametersChanged() {
        guard isActive else {
            return
        }
        guard shieldWindowsController?.rebuildShields() == true else {
            WardLogger.cleaningMode.error("Shields could not be rebuilt after a display change; exiting.")
            exitCleaningMode()
            return
        }
    }
}
