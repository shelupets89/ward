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
@MainActor
public final class ExpiryTimer {
    private let interval: TimeInterval
    private let onTick: @MainActor () -> Void
    private var scheduledTimer: Timer?

    public init(interval: TimeInterval, onTick: @escaping @MainActor () -> Void) {
        self.interval = interval
        self.onTick = onTick
    }

    public func start() {
        stop()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.onTick()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        scheduledTimer = timer
    }

    public func stop() {
        scheduledTimer?.invalidate()
        scheduledTimer = nil
    }
}
