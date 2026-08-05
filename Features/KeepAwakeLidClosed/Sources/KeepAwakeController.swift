import AppKit
import WardKit

/// Keeps the Mac running with the lid closed, for a bounded stretch.
///
/// This is deliberately NOT wired into cleaning mode: the two have opposite
/// failure models. Cleaning mode fails open — kill the process and every
/// restriction dies with it. Keep-awake fails *closed*: the setting it flips
/// outlives the process, so this type carries its own safety net (a hard
/// expiry, a restore on quit, and a leak check).
@MainActor
public final class KeepAwakeController: NSObject {
    private static let expiryCheckInterval: TimeInterval = 30

    /// What the menu should offer. Derived from the live system flag rather than
    /// from `session` alone, so a setting this app doesn't own — left by a crash,
    /// or by another tool — can never be reported as "off".
    enum MenuState: Equatable {
        case off
        case awaitingConfirmation
        case active(remainingTime: String)
        case unownedAndDisabled
    }

    private var session: KeepAwakeSession?
    private var expiryTimer: Timer?
    private var isAwaitingConfirmation = false
    private var hasWarnedAboutFailedRestore = false
    private var hasOfferedPasswordlessSetup = false
    /// `sudo -n -l` spawns a process; the answer only changes when the rule is
    /// installed or removed, so it is cached rather than probed per menu open.
    private var cachedPasswordlessAvailability: Bool?

    public override init() {
        super.init()
    }

    @objc func startFromMenu(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? KeepAwakeDuration else {
            return
        }
        Task {
            await start(for: option)
        }
    }

    @objc func stopFromMenu() {
        guard stop(allowInteractivePrompt: true) else {
            presentAlert(
                messageText: "Sleep is still disabled",
                informativeText: """
                Restoring normal sleep needs administrator rights, and the authorization was \
                declined or failed.
                """
            )
            return
        }
    }

    @objc func restoreFromMenu() {
        offerToRestoreUnownedSetting()
    }

    @objc func setUpPasswordlessFromMenu() {
        setUpPasswordlessToggle()
    }

    var isHoldingSleepDisabled: Bool {
        return session != nil
    }

    var menuState: MenuState {
        if isAwaitingConfirmation {
            return .awaitingConfirmation
        }
        if let session {
            return .active(remainingTime: session.remaining(at: .now).formatted(.time(pattern: .hourMinute)))
        }
        return LidSleepSetting.currentState.mayBeDisabled ? .unownedAndDisabled : .off
    }

    /// Turning this on is gated behind Touch ID; turning it off deliberately is
    /// not. A safety path that can be declined is not a safety path.
    ///
    /// The gate is skipped when the toggle would raise a password dialog anyway
    /// — two prompts for one action is worse than the one it already needs.
    func start(for option: KeepAwakeDuration) async {
        guard session == nil, !isAwaitingConfirmation else {
            return
        }
        guard await confirmIntentIfPromptWouldBeTheOnlyOne(for: option) else {
            WardLogger.keepAwake.notice("Keep-awake cancelled at the confirmation prompt.")
            return
        }
        // The confirmation above suspends; re-check rather than trusting the
        // state we validated before it.
        guard session == nil else {
            WardLogger.keepAwake.notice("Ignoring a stale start — a session already exists.")
            return
        }
        guard LidSleepSetting.disableSleep(allowInteractivePrompt: true) else {
            WardLogger.keepAwake.error("Could not disable lid sleep; keep-awake not started.")
            presentAlert(
                messageText: "Ward couldn’t change the sleep setting",
                informativeText: """
                Disabling lid sleep needs administrator rights, and the authorization was declined \
                or failed. Run scripts/install-sudoers-rule.sh once if you would rather not be \
                asked each time.
                """
            )
            return
        }
        session = KeepAwakeSession(startedAt: .now, duration: option.duration)
        hasWarnedAboutFailedRestore = false
        startExpiryTimer()
        WardLogger.keepAwake.info("Keep-awake active for \(option.menuTitle, privacy: .public).")
    }

    /// Returns false only on an explicit decline. The expiry timer is left
    /// running on failure so it keeps retrying — a restore that failed once is
    /// exactly when the safety net matters most.
    @discardableResult
    func stop(allowInteractivePrompt: Bool) -> Bool {
        guard session != nil else {
            return true
        }
        guard LidSleepSetting.enableSleep(allowInteractivePrompt: allowInteractivePrompt) else {
            WardLogger.keepAwake.error("Could not restore lid sleep — it is still disabled.")
            return false
        }
        stopExpiryTimer()
        session = nil
        hasWarnedAboutFailedRestore = false
        WardLogger.keepAwake.info("Keep-awake stopped; lid sleep restored.")
        return true
    }

    /// A crash or force-quit leaves the flag set with no session to expire it.
    /// Nothing at launch can belong to this process, so a set flag is a leak.
    func offerToRestoreUnownedSetting() {
        guard session == nil, LidSleepSetting.currentState.mayBeDisabled else {
            return
        }
        WardLogger.keepAwake.notice("Lid sleep is disabled but unowned — offering to restore.")
        let alert = NSAlert()
        alert.messageText = "This Mac is set to stay awake with the lid closed"
        alert.informativeText = """
        Ward (or something else) left lid sleep disabled, and that setting survives quitting and \
        restarting. Restore normal sleep now?
        """
        alert.addButton(withTitle: "Restore Normal Sleep")
        alert.addButton(withTitle: "Leave It Disabled")
        guard alert.runModal() == .alertFirstButtonReturn else {
            WardLogger.keepAwake.notice("User chose to leave lid sleep disabled.")
            return
        }
        guard LidSleepSetting.enableSleep(allowInteractivePrompt: true) else {
            WardLogger.keepAwake.error("Restore declined or failed; lid sleep remains disabled.")
            presentAlert(
                messageText: "Sleep is still disabled",
                informativeText: """
                Restoring normal sleep needs administrator rights, and the authorization was \
                declined or failed. Ward will keep offering from the menu, or you can run \
                `sudo pmset -a disablesleep 0` yourself.
                """
            )
            return
        }
        WardLogger.keepAwake.info("Unowned lid-sleep setting restored.")
    }

    var needsPasswordlessSetup: Bool {
        return !isPasswordlessToggleAvailable
    }

    /// Offers the one-time setup, then re-probes. Safe to call repeatedly.
    func setUpPasswordlessToggle() {
        hasOfferedPasswordlessSetup = true
        _ = SudoersRuleInstaller.offerInstallation()
        cachedPasswordlessAvailability = nil
    }

    private var isPasswordlessToggleAvailable: Bool {
        if let cachedPasswordlessAvailability {
            return cachedPasswordlessAvailability
        }
        let isAvailable = LidSleepSetting.isPasswordlessToggleAvailable
        cachedPasswordlessAvailability = isAvailable
        return isAvailable
    }

    private func confirmIntentIfPromptWouldBeTheOnlyOne(for option: KeepAwakeDuration) async -> Bool {
        if needsPasswordlessSetup, !hasOfferedPasswordlessSetup {
            setUpPasswordlessToggle()
        }
        guard isPasswordlessToggleAvailable else {
            WardLogger.keepAwake.info("No passwordless toggle available; skipping the Touch ID gate.")
            return true
        }
        isAwaitingConfirmation = true
        defer { isAwaitingConfirmation = false }
        return await BiometricConfirmation.confirmUserPresence(
            reason: "keep this Mac awake with the lid closed for \(option.menuTitle)"
        )
    }

    private func startExpiryTimer() {
        stopExpiryTimer()
        let timer = Timer(timeInterval: Self.expiryCheckInterval, repeats: true) { [weak self] _ in
            // Timers on the main run loop fire on the main thread.
            MainActor.assumeIsolated {
                self?.expireSessionIfElapsed()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func expireSessionIfElapsed() {
        guard let session, session.isExpired(at: .now) else {
            return
        }
        WardLogger.keepAwake.info("Keep-awake expired; restoring lid sleep.")
        guard !stop(allowInteractivePrompt: false) else {
            return
        }
        // The timer keeps retrying, so warn once rather than every 30 seconds.
        guard !hasWarnedAboutFailedRestore else {
            return
        }
        hasWarnedAboutFailedRestore = true
        presentAlert(
            messageText: "Keep Awake expired but sleep is still disabled",
            informativeText: """
            The time limit ran out, but restoring normal sleep needs administrator rights. \
            Choose Turn Off Keep Awake from the menu to authorize it. Installing \
            scripts/install-sudoers-rule.sh lets Ward do this on its own next time.
            """
        )
    }

    private func stopExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    private func presentAlert(messageText: String, informativeText: String) {
        let alert = NSAlert()
        alert.messageText = messageText
        alert.informativeText = informativeText
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
