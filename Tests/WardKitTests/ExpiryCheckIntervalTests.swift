import Foundation
import Testing
@testable import WardKit

/// A non-positive interval is the one input that makes `Timer` do the opposite
/// of what it looks like — spinning at thousands of ticks a second rather than
/// never firing. These cases pin the floor that keeps that out of a shipped
/// build, where the assert beside it has been compiled away.
struct ExpiryCheckIntervalTests {
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

    @Test("Never returns something a Timer would spin on")
    func neverReturnsASpinningInterval() {
        let awkwardInputs: [TimeInterval] = [-.greatestFiniteMagnitude, -1, 0, .leastNonzeroMagnitude, 0.5]
        for input in awkwardInputs {
            #expect(ExpiryCheckInterval.clamped(input) >= ExpiryCheckInterval.shortest)
        }
    }
}
