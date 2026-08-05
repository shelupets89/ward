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

    public let requiredHoldDuration: Duration
    public private(set) var state: HoldState = .idle(areModifiersDown: false)

    public init(requiredHoldDuration: Duration = .seconds(5)) {
        precondition(requiredHoldDuration > .zero, "requiredHoldDuration must be positive")
        self.requiredHoldDuration = requiredHoldDuration
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
