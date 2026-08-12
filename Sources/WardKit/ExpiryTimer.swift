import Foundation

/// The repeating check a capped session needs in order to end itself.
///
/// It polls rather than firing once at the deadline, and that is the whole
/// point. Sessions are measured with `ContinuousClock`, which keeps counting
/// while the Mac is asleep, whereas a run-loop timer does not — so a one-shot
/// scheduled eight hours out would come back late by however long the machine
/// slept. Re-asking "is it expired yet?" is immune to that.
///
/// Centralising it also keeps the `assumeIsolated` bridge out of every capped
/// feature: `Timer`'s callback is `@Sendable`, but a timer added to
/// `RunLoop.main` always fires on the main thread, so asserting that isolation
/// is correct rather than a workaround.
///
/// `onTick` is retained for the timer's lifetime, so a closure reaching back to
/// whatever owns this timer — through the `CappedSession` holding it — has to
/// capture weakly.
///
/// Not `public`: `CappedSession` is the only caller. That does not by itself
/// stop a feature from disarming early — a bare `Foundation.Timer` is always
/// within reach. What keeps the bug from being re-expressible is that neither
/// controller holds a timer-shaped property at all.
///
/// There is deliberately no `deinit` invalidating the timer: firing on a live
/// session it would disarm the check while restoring nothing — the ordering bug
/// `CappedSession` exists to prevent. It is also a Swift 6 language-mode error.
@MainActor
final class ExpiryTimer {
    let interval: TimeInterval
    private let onTick: @MainActor () -> Void
    private var scheduledTimer: Timer?

    init(interval: TimeInterval, onTick: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    /// Whether the check is currently armed.
    ///
    /// Read by `CappedSession`, and through it by the tests that hold the
    /// restore-before-disarm ordering in place: that a failed end leaves this
    /// `true` is the whole property under test. Nothing in the app itself asks.
    var isScheduled: Bool {
        return scheduledTimer != nil
    }

    /// How many times the check has been armed.
    ///
    /// `start()` always replaces, so `isScheduled` reads the same whether a
    /// check was restarted or never touched. This tells them apart, which is
    /// what lets a test pin that a refused start leaves the running session's
    /// next poll where it was.
    private(set) var timesArmed = 0

    func start() {
        stop()
        timesArmed += 1
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduledTimer = timer
    }

    func stop() {
        scheduledTimer?.invalidate()
        scheduledTimer = nil
    }
}
