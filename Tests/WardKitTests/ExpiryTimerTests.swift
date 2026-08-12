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
