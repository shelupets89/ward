/// State machine for the "hold esc alone for N seconds" exit gesture.
///
/// Exit must be deliberate: a cloth wiping the keyboard can hold esc together
/// with surrounding keys, so any other key press or modifier suppresses the
/// hold until esc is physically released. Auto-repeat key-downs can never
/// start or restart a hold on their own.
///
/// Timing uses `ContinuousClock`, which keeps counting across system sleep and
/// is immune to wall-clock jumps — an NTP correction mid-hold must not shorten
/// or extend the gesture.
public struct EscapeHoldTracker {
    /// The modifier flag rides inside the non-holding cases rather than beside
    /// them, so "holding while a modifier is down" cannot be represented.
    public enum HoldState: Equatable {
        case idle(areModifiersDown: Bool)
        case holding(startedAt: ContinuousClock.Instant)
        case suppressedUntilRelease(areModifiersDown: Bool)
    }

    /// The gesture the feature ships with, and what an unusable one falls back
    /// to.
    public static let defaultHoldDuration: Duration = .seconds(5)

    public let requiredHoldDuration: Duration
    public private(set) var state: HoldState = .idle(areModifiersDown: false)

    public init(requiredHoldDuration: Duration = Self.defaultHoldDuration) {
        // `clampedHoldDuration` is what actually holds the gesture usable. This
        // only speaks up in a debug build that constructs one badly, which no
        // path here currently does — as a `precondition` it would fire while
        // `AppDelegate` builds its feature list, ahead of every feature's
        // `recoverLeakedState()`, and so take out the lid-closed restore offer
        // on a Mac still carrying the setting a crash left behind.
        assert(requiredHoldDuration > .zero, "requiredHoldDuration must be positive")
        self.requiredHoldDuration = Self.clampedHoldDuration(requiredHoldDuration)
    }

    /// The hold the gesture actually runs, which is the requested one only once
    /// it is positive.
    ///
    /// Applied rather than checked, because the two unusable values fail in
    /// opposite directions and neither is a gesture: zero divides to `inf` in
    /// `progress`, completing on the first key-down so a cloth leaves cleaning
    /// mode, while a negative one clamps to zero progress and never completes
    /// at all, leaving input blocked with the documented exit unable to fire.
    ///
    /// Falls back to the shipped hold rather than to a short floor — a floor
    /// would answer this by quietly weakening the gesture the feature is for.
    public static func clampedHoldDuration(_ requested: Duration) -> Duration {
        guard requested > .zero else {
            return defaultHoldDuration
        }
        return requested
    }

    public var areModifiersDown: Bool {
        switch state {
        case .idle(let areModifiersDown), .suppressedUntilRelease(let areModifiersDown):
            return areModifiersDown
        case .holding:
            return false
        }
    }

    public mutating func registerEscapeKeyDown(at instant: ContinuousClock.Instant) {
        guard case .idle(let areModifiersDown) = state else {
            return
        }
        if areModifiersDown {
            state = .suppressedUntilRelease(areModifiersDown: true)
        } else {
            state = .holding(startedAt: instant)
        }
    }

    public mutating func registerEscapeKeyUp() {
        state = .idle(areModifiersDown: areModifiersDown)
    }

    public mutating func registerOtherKeyDown() {
        suppressActiveHold()
    }

    public mutating func updateModifiersDown(_ areModifiersDown: Bool) {
        switch state {
        case .idle:
            state = .idle(areModifiersDown: areModifiersDown)
        case .suppressedUntilRelease:
            state = .suppressedUntilRelease(areModifiersDown: areModifiersDown)
        case .holding:
            if areModifiersDown {
                state = .suppressedUntilRelease(areModifiersDown: true)
            }
        }
    }

    public mutating func reset() {
        state = .idle(areModifiersDown: false)
    }

    public var isHolding: Bool {
        guard case .holding = state else {
            return false
        }
        return true
    }

    public func progress(at instant: ContinuousClock.Instant) -> Double {
        guard case .holding(let startedAt) = state else {
            return 0
        }
        let elapsed = startedAt.duration(to: instant)
        let elapsedFraction = elapsed / requiredHoldDuration
        return min(1, max(0, elapsedFraction))
    }

    public func isComplete(at instant: ContinuousClock.Instant) -> Bool {
        return progress(at: instant) >= 1
    }

    private mutating func suppressActiveHold() {
        if case .holding = state {
            state = .suppressedUntilRelease(areModifiersDown: false)
        }
    }
}
