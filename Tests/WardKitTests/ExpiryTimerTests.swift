import Foundation
import Testing
@testable import WardKit

/// `timesArmed` is what lets `CappedSessionTests` tell a check that was left
/// alone from one that was stopped and replaced. These cases hold the counter
/// itself honest, so that distinction cannot quietly stop working while the
/// case relying on it stays green.
///
/// Isolated to the main actor because `ExpiryTimer` is: its check is a `Timer`
/// on `RunLoop.main`.
@MainActor
@Suite(.serialized)
struct ExpiryTimerTests {
    /// Long enough that the check cannot fire during a test. These cases assert
    /// on arming, never on ticking.
    private static let neverFiresWithinATest: TimeInterval = 3600

    private func makeTimer() -> ExpiryTimer {
        return ExpiryTimer(interval: Self.neverFiresWithinATest, onTick: {})
    }

    @Test("Counts nothing before the check is ever armed")
    func countsNothingBeforeArming() {
        #expect(makeTimer().timesArmed == 0)
    }

    @Test("Counts exactly one arming per start")
    func countsOneArmingPerStart() {
        let timer = makeTimer()

        timer.start()
        #expect(timer.timesArmed == 1)
        timer.start()
        #expect(timer.timesArmed == 2)

        timer.stop()
    }

    /// Stopping is not arming. A counter that moved here too would report a
    /// restart that never happened.
    @Test("Leaves the count where it was when the check is stopped")
    func stoppingDoesNotCount() {
        let timer = makeTimer()
        timer.start()

        timer.stop()

        #expect(timer.timesArmed == 1)
    }

    /// The only case here that lets a timer actually fire, and the only one that
    /// would notice `repeats:` becoming false. That matters most for the
    /// lid-closed feature, where the tick is the *only* thing that reaches the
    /// expiry sweep — nothing re-checks on a menu open — so a check that fired
    /// once and stopped would leave the setting on with nothing coming back for
    /// it.
    ///
    /// Bounded by a `ContinuousClock` deadline and returns the moment it has
    /// seen enough, so the cost is a few milliseconds unless it is failing.
    /// `CFRunLoopRunInMode` rather than `RunLoop.run(until:)` because that one
    /// wants a `Date`, which is not what this repo measures time with.
    @Test("Keeps checking, rather than firing once and stopping")
    func keepsCheckingRatherThanFiringOnce() {
        var tickCount = 0
        let timer = ExpiryTimer(interval: 0.02) {
            tickCount += 1
        }
        timer.start()

        let deadline = ContinuousClock.now.advanced(by: .seconds(5))
        while tickCount < 2, ContinuousClock.now < deadline {
            CFRunLoopRunInMode(.defaultMode, 0.01, true)
        }
        timer.stop()

        #expect(tickCount >= 2, "a one-shot check stops after its first tick and never comes back")
    }

    @Test("Arms and disarms the check")
    func armsAndDisarmsTheCheck() {
        let timer = makeTimer()
        #expect(timer.isScheduled == false)

        timer.start()
        #expect(timer.isScheduled)

        timer.stop()
        #expect(timer.isScheduled == false)
    }
}
