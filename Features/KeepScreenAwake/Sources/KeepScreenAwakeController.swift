import AppKit
import WardKit

/// Holds a display-sleep assertion for a bounded stretch, so a long read or a
/// video doesn't need the mouse nudged every few minutes.
///
/// This **fails open**: the assertion is owned by the process and IOKit drops it
/// when the process goes, so a crash restores normal display sleep on its own.
/// That is why there is no leak check, no quit gate and nothing persisted — the
/// cap exists for predictability with the other keep-awake features, not as a
/// safety net.
///
/// Shares nothing with `KeepAwakeController` beyond the name: that one flips a
/// system setting that outlives the process and carries the recovery machinery
/// to match.
@MainActor
public final class KeepScreenAwakeController: NSObject {
    private static let expiryCheckInterval: TimeInterval = 30

    /// Its own instance, not one shared with cleaning mode. Each preventer owns
    /// a separate `IOPMAssertionID`, so neither feature's release can cancel the
    /// other's assertion.
    private let displaySleepPreventer = DisplaySleepPreventer(assertionName: "Ward Keep Screen Awake")
    private var session: KeepAwakeSession?
    private var expiryTimer: Timer?

    public override init() {
        super.init()
    }

    @objc func startFromMenu(_ sender: NSMenuItem) {
        guard let option = sender.representedObject as? KeepAwakeDuration else {
            return
        }
        start(for: option)
    }

    @objc func stopFromMenu() {
        guard stop() else {
            presentReleaseFailedAlert()
            return
        }
    }

    /// Derived on every read rather than cached, so the cap passing between two
    /// expiry checks can never leave the menu offering to turn off a session
    /// that has already run out.
    var state: KeepScreenAwakeState {
        return KeepScreenAwakeState(session: session, at: .now)
    }

    func start(for option: KeepAwakeDuration) {
        endSessionIfExpired()
        guard session == nil else {
            return
        }
        guard displaySleepPreventer.beginPreventingDisplaySleep() else {
            WardLogger.keepScreenAwake.error("Display sleep assertion failed; Keep Screen Awake not started.")
            presentAssertionFailedAlert()
            return
        }
        session = KeepAwakeSession(startedAt: .now, duration: option.duration)
        startExpiryTimer()
        WardLogger.keepScreenAwake.info("Keep Screen Awake active for \(option.menuTitle, privacy: .public).")
    }

    /// Releases first and only then forgets the session, so a refused release
    /// leaves the timer running to retry and the menu still showing an active
    /// session — which is the truth. Tearing down first would report "off"
    /// while the screen was still held awake.
    @discardableResult
    func stop() -> Bool {
        guard session != nil else {
            return true
        }
        guard displaySleepPreventer.endPreventingDisplaySleep() else {
            WardLogger.keepScreenAwake.error("Display assertion refused to release; the screen is still held awake.")
            return false
        }
        stopExpiryTimer()
        session = nil
        WardLogger.keepScreenAwake.info("Keep Screen Awake stopped; the display can sleep again.")
        return true
    }

    /// Releasing at the cap is the timer's job, but a menu can open between two
    /// ticks. Sweeping here too keeps what the menu says and what the power
    /// assertion actually is from disagreeing.
    func endSessionIfExpired() {
        guard let session, session.isExpired(at: .now) else {
            return
        }
        WardLogger.keepScreenAwake.info("Keep Screen Awake reached its time cap.")
        stop()
    }

    private func startExpiryTimer() {
        stopExpiryTimer()
        let timer = Timer(timeInterval: Self.expiryCheckInterval, repeats: true) { [weak self] _ in
            // Timers on the main run loop fire on the main thread.
            MainActor.assumeIsolated {
                self?.endSessionIfExpired()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        expiryTimer = timer
    }

    private func stopExpiryTimer() {
        expiryTimer?.invalidate()
        expiryTimer = nil
    }

    /// The assertion is the entire feature, so a failed one is silent breakage:
    /// the user would sit back expecting the screen to stay on and watch it
    /// sleep anyway.
    private func presentAssertionFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Ward couldn’t keep the screen awake"
        alert.informativeText = """
        macOS refused the power assertion, so the display will still sleep on its usual schedule. \
        Try again in a moment.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    /// Only raised for a deliberate Turn Off. The expiry sweep stays silent and
    /// lets the timer retry — a dialog every 30 seconds would be worse than the
    /// menu simply continuing to show the session as active.
    private func presentReleaseFailedAlert() {
        let alert = NSAlert()
        alert.messageText = "Ward couldn’t release the screen"
        alert.informativeText = """
        macOS refused to drop the power assertion, so the display is still being kept awake. \
        Ward will keep trying, and quitting Ward releases it for certain.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
