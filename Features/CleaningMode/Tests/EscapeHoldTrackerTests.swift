import XCTest
@testable import CleaningMode

final class EscapeHoldTrackerTests: XCTestCase {
    private func makeTracker() -> EscapeHoldTracker {
        return EscapeHoldTracker(requiredHoldDuration: .seconds(5))
    }

    func test_shouldReportZeroProgress_whenIdle() {
        let tracker = makeTracker()
        let now = ContinuousClock.now
        XCTAssertEqual(tracker.state, .idle(areModifiersDown: false))
        XCTAssertEqual(tracker.progress(at: now), 0)
        XCTAssertFalse(tracker.isHolding)
    }

    func test_shouldStartHolding_whenEscapePressedFromIdle() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        XCTAssertEqual(tracker.state, .holding(startedAt: now))
        XCTAssertTrue(tracker.isHolding)
    }

    func test_shouldReportElapsedFraction_whileHolding() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        let halfwayInstant = now.advanced(by: .seconds(2.5))
        XCTAssertEqual(tracker.progress(at: halfwayInstant), 0.5, accuracy: 0.0001)
    }

    func test_shouldClampProgressToOne_whenHeldBeyondRequiredDuration() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        let wellPastInstant = now.advanced(by: .seconds(60))
        XCTAssertEqual(tracker.progress(at: wellPastInstant), 1)
    }

    func test_shouldClampProgressToZero_whenInstantIsBeforeHoldStarted() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        let earlierInstant = now.advanced(by: .seconds(-10))
        XCTAssertEqual(tracker.progress(at: earlierInstant), 0)
        XCTAssertFalse(tracker.isComplete(at: earlierInstant))
    }

    func test_shouldComplete_whenHeldForRequiredDuration() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        XCTAssertTrue(tracker.isComplete(at: now.advanced(by: .seconds(5))))
    }

    func test_shouldNotComplete_whenHeldShorterThanRequiredDuration() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        XCTAssertFalse(tracker.isComplete(at: now.advanced(by: .seconds(4.9))))
    }

    func test_shouldResetToIdle_whenEscapeReleasedMidHold() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.registerEscapeKeyUp()
        XCTAssertEqual(tracker.state, .idle(areModifiersDown: false))
        XCTAssertEqual(tracker.progress(at: now.advanced(by: .seconds(10))), 0)
    }

    func test_shouldStayIdle_whenEscapeReleasedRepeatedlyFromIdle() {
        var tracker = makeTracker()
        tracker.registerEscapeKeyUp()
        tracker.registerEscapeKeyUp()
        XCTAssertEqual(tracker.state, .idle(areModifiersDown: false))
    }

    func test_shouldKeepOriginalStart_whenAutorepeatEscapeKeyDownsArrive() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.registerEscapeKeyDown(at: now.advanced(by: .seconds(2)))
        XCTAssertEqual(tracker.state, .holding(startedAt: now))
    }

    func test_shouldSuppressHold_whenOtherKeyPressedDuringHold() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.registerOtherKeyDown()
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: false))
        XCTAssertEqual(tracker.progress(at: now.advanced(by: .seconds(10))), 0)
    }

    func test_shouldStayIdle_whenOtherKeyPressedWhileIdle() {
        var tracker = makeTracker()
        tracker.registerOtherKeyDown()
        XCTAssertEqual(tracker.state, .idle(areModifiersDown: false))
    }

    func test_shouldStaySuppressed_whenOtherKeyPressedWhileAlreadySuppressed() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.registerOtherKeyDown()
        tracker.registerOtherKeyDown()
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: false))
    }

    func test_shouldIgnoreEscapeKeyDowns_whileSuppressed() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.registerOtherKeyDown()
        tracker.registerEscapeKeyDown(at: now.advanced(by: .seconds(1)))
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: false))
        XCTAssertFalse(tracker.isComplete(at: now.advanced(by: .seconds(60))))
    }

    func test_shouldClearSuppression_whenEscapeReleased() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.registerOtherKeyDown()
        tracker.registerEscapeKeyUp()
        XCTAssertEqual(tracker.state, .idle(areModifiersDown: false))
        let repressInstant = now.advanced(by: .seconds(2))
        tracker.registerEscapeKeyDown(at: repressInstant)
        XCTAssertEqual(tracker.state, .holding(startedAt: repressInstant))
    }

    func test_shouldNotStartHold_whenModifiersAreDown() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.updateModifiersDown(true)
        tracker.registerEscapeKeyDown(at: now)
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: true))
    }

    func test_shouldSuppressHold_whenModifierPressedDuringHold() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.updateModifiersDown(true)
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: true))
    }

    func test_shouldUpdateSuppressedModifierFlag_whenModifiersChangeWhileSuppressed() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.registerOtherKeyDown()
        tracker.updateModifiersDown(true)
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: true))
        tracker.updateModifiersDown(false)
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: false))
    }

    func test_shouldNotResumeHold_whenModifiersReleasedWhileEscapeStillDown() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.updateModifiersDown(true)
        tracker.registerEscapeKeyDown(at: now)
        tracker.updateModifiersDown(false)
        tracker.registerEscapeKeyDown(at: now.advanced(by: .seconds(1)))
        XCTAssertEqual(tracker.state, .suppressedUntilRelease(areModifiersDown: false))
    }

    func test_shouldStartHold_afterModifiersReleasedAndEscapeRepressed() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.updateModifiersDown(true)
        tracker.registerEscapeKeyDown(at: now)
        tracker.updateModifiersDown(false)
        tracker.registerEscapeKeyUp()
        let repressInstant = now.advanced(by: .seconds(3))
        tracker.registerEscapeKeyDown(at: repressInstant)
        XCTAssertEqual(tracker.state, .holding(startedAt: repressInstant))
    }

    func test_shouldReturnToIdle_onReset() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.updateModifiersDown(true)
        tracker.registerEscapeKeyDown(at: now)
        tracker.reset()
        XCTAssertEqual(tracker.state, .idle(areModifiersDown: false))
        XCTAssertFalse(tracker.areModifiersDown)
    }

    func test_shouldReturnToIdle_whenResetWhileHolding() {
        var tracker = makeTracker()
        let now = ContinuousClock.now
        tracker.registerEscapeKeyDown(at: now)
        tracker.reset()
        XCTAssertEqual(tracker.state, .idle(areModifiersDown: false))
        XCTAssertFalse(tracker.isHolding)
    }
}

/// A non-positive hold divides `progress` by zero or by a negative, and neither
/// result is a gesture: zero completes on the first key-down, so a cloth leaves
/// cleaning mode, and a negative one never reaches 1 at all, so the shield keeps
/// input blocked with the exit it documents unable to fire. These cases pin the
/// fallback that keeps both out of a shipped build, where the assert beside it
/// has been compiled away.
final class EscapeHoldDurationTests: XCTestCase {
    func test_shouldFallBackToTheDefaultHold_whenGivenZero() {
        XCTAssertEqual(EscapeHoldTracker.clampedHoldDuration(.zero), EscapeHoldTracker.defaultHoldDuration)
    }

    func test_shouldFallBackToTheDefaultHold_whenGivenANegativeHold() {
        XCTAssertEqual(EscapeHoldTracker.clampedHoldDuration(.seconds(-5)), EscapeHoldTracker.defaultHoldDuration)
    }

    /// Falls back to the shipped hold rather than a short floor: a floor would
    /// answer the crash by quietly weakening the gesture the feature exists for.
    func test_shouldFallBackToFiveSeconds_ratherThanToAShorterFloor() {
        XCTAssertEqual(EscapeHoldTracker.defaultHoldDuration, .seconds(5))
    }

    /// The hold the controller actually passes. Clamping must be invisible to
    /// every real caller, including ones asking for a longer, stricter gesture.
    func test_shouldPassThroughTheHoldsRealCallersUse() {
        for requested in [Duration.seconds(5), .seconds(1), .seconds(30)] {
            XCTAssertEqual(EscapeHoldTracker.clampedHoldDuration(requested), requested)
        }
    }

    func test_shouldNeverReturnAHoldThatProgressCannotDivideBy() {
        for requested in [Duration.zero, .seconds(-1), .milliseconds(-1), .seconds(-99999)] {
            XCTAssertGreaterThan(EscapeHoldTracker.clampedHoldDuration(requested), .zero)
        }
    }
}
