/// A bounded stretch of staying awake.
///
/// Every session carries a deadline, but the cap means different things to its
/// two users, and conflating them would be dangerous. For lid-closed keep-awake
/// it is a genuine safety feature: that one disables a system setting outliving
/// this process, so an open-ended session means a forgotten laptop cooking in a
/// bag. For screen keep-awake it is only predictability — a power assertion
/// dies with the process, so overrunning costs nothing.
///
/// Timing uses `ContinuousClock` for the same reason the exit gesture does: a
/// wall-clock jump must not shorten or extend it.
public struct KeepAwakeSession: Equatable, Sendable {
    public let startedAt: ContinuousClock.Instant
    public let duration: Duration

    public init(startedAt: ContinuousClock.Instant, duration: Duration) {
        // Deliberately not a `precondition`: the lid-closed caller reaches here
        // only once `pmset disablesleep 1` has already succeeded, so a release
        // trap would strand exactly the setting this type exists to bound.
        //
        // Nothing is clamped alongside it, unlike `ExpiryCheckInterval`. A
        // non-positive duration puts `expiresAt` at or before `startedAt`, so
        // the session is born expired and the first check restores sleep —
        // already the direction a fail-closed feature has to fail in. Rounding
        // one up to something usable would hold the setting for a stretch
        // nobody asked for, which is the failure worth avoiding here.
        //
        // `KeepAwakeDuration` is what holds real callers positive, and
        // `KeepAwakeDurationTests` is where that is checked.
        assert(duration > .zero, "duration must be positive")
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
