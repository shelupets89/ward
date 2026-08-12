import Foundation
import Testing
@testable import WardKit

/// A non-positive interval is the one input that makes `Timer` do the opposite
/// of what it looks like — spinning at thousands of ticks a second rather than
/// never firing. These cases pin the floor that keeps that out of a shipped
/// build, where the assert beside it has been compiled away.
struct ExpiryCheckIntervalTests {
    /// Pinned rather than compared to itself. Every other case here asks only
    /// that the floor is self-consistent, which a decimal-point slip would
    /// satisfy just as well — and a floor of a millisecond still spins.
    @Test("Puts the floor at one second")
    func floorIsOneSecond() {
        #expect(ExpiryCheckInterval.shortest == 1)
    }

    @Test("Holds a zero interval up to the floor rather than letting it spin")
    func clampsZero() {
        #expect(ExpiryCheckInterval.clamped(0) == ExpiryCheckInterval.shortest)
    }

    @Test("Holds a negative interval up to the floor")
    func clampsNegative() {
        #expect(ExpiryCheckInterval.clamped(-30) == ExpiryCheckInterval.shortest)
    }

    @Test("Holds an interval below the floor up to it")
    func clampsBelowTheFloor() {
        #expect(ExpiryCheckInterval.clamped(0.0001) == ExpiryCheckInterval.shortest)
    }

    @Test("Leaves the floor itself alone")
    func leavesTheFloorAlone() {
        #expect(ExpiryCheckInterval.clamped(ExpiryCheckInterval.shortest) == ExpiryCheckInterval.shortest)
    }

    /// The interval both features actually pass, and the one the tests use.
    /// Clamping must be invisible to every real caller.
    @Test("Passes through the intervals real callers use", arguments: [30.0, 3600.0])
    func passesThroughRealIntervals(interval: TimeInterval) {
        #expect(ExpiryCheckInterval.clamped(interval) == interval)
    }

    /// `nan` is the input `max` cannot hold, since every comparison against it
    /// is false — it would come straight back out and reach `Timer` unclamped.
    @Test("Holds a nan interval up to the floor rather than passing it through")
    func clampsNotANumber() {
        #expect(ExpiryCheckInterval.clamped(.nan) == ExpiryCheckInterval.shortest)
    }

    /// An infinite interval is the failure the other direction: a check that
    /// never fires at all, on a session whose cap it exists to enforce.
    @Test("Holds an infinite interval down to the floor", arguments: [TimeInterval.infinity, -.infinity])
    func clampsInfinite(interval: TimeInterval) {
        #expect(ExpiryCheckInterval.clamped(interval) == ExpiryCheckInterval.shortest)
    }

    @Test("Never returns something a Timer would spin on, or never fire on")
    func neverReturnsAnUnusableInterval() {
        let awkwardInputs: [TimeInterval] = [
            -.greatestFiniteMagnitude, -1, 0, .leastNonzeroMagnitude, 0.5,
            .nan, .infinity, -.infinity, .signalingNaN
        ]
        for input in awkwardInputs {
            let clamped = ExpiryCheckInterval.clamped(input)
            #expect(clamped.isFinite)
            #expect(clamped >= ExpiryCheckInterval.shortest)
        }
    }
}
