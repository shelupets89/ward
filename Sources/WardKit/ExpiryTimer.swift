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
/// `onTick` is retained for the timer's lifetime, so a controller that owns its
/// `ExpiryTimer` must capture itself weakly in the closure.
///
/// Deliberately not `public`. `CappedSession` is the only thing that may own
/// one, and keeping this inside WardKit is what makes that true by compilation
/// rather than by agreement: a feature target cannot build a second timer to
/// disarm ahead of the restore, which is the bug the pair exists to prevent.
@MainActor
final class ExpiryTimer {
    private let interval: TimeInterval
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

    func start() {
        stop()
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

    /// `RunLoop.main` holds the scheduled timer, so an abandoned `ExpiryTimer`
    /// would otherwise leave one firing into a `[weak self]` that is already
    /// gone — harmless, but it never stops.
    deinit {
        scheduledTimer?.invalidate()
    }
}
