/// A bounded stretch of "stay awake with the lid closed".
///
/// Every session carries a deadline. Disabling lid sleep changes persistent
/// system state that outlives this process, so an open-ended session would mean
/// a forgotten laptop cooking in a bag — the cap is the safety feature, not a
/// convenience. Timing uses `ContinuousClock` for the same reason the exit
/// gesture does: a wall-clock jump must not shorten or extend it.
public struct KeepAwakeSession: Equatable, Sendable {
    public let startedAt: ContinuousClock.Instant
    public let duration: Duration

    public init(startedAt: ContinuousClock.Instant, duration: Duration) {
        precondition(duration > .zero, "duration must be positive")
        self.startedAt = startedAt
        self.duration = duration
    }

    public var expiresAt: ContinuousClock.Instant {
        return startedAt.advanced(by: duration)
    }

    public func isExpired(at instant: ContinuousClock.Instant) -> Bool {
        return instant >= expiresAt
    }

    public func remaining(at instant: ContinuousClock.Instant) -> Duration {
        return max(.zero, instant.duration(to: expiresAt))
    }
}

public enum KeepAwakeDuration: CaseIterable, Sendable {
    case thirtyMinutes
    case twoHours
    case eightHours

    public var duration: Duration {
        switch self {
        case .thirtyMinutes:
            return .seconds(30 * 60)
        case .twoHours:
            return .seconds(2 * 3600)
        case .eightHours:
            return .seconds(8 * 3600)
        }
    }

    public var menuTitle: String {
        switch self {
        case .thirtyMinutes:
            return "30 minutes"
        case .twoHours:
            return "2 hours"
        case .eightHours:
            return "8 hours"
        }
    }
}
