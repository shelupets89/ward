import WardKit

/// What the Keep Screen Awake menu should show, derived from the session alone.
///
/// Unlike its lid-closed namesake there is no system setting to consult: the
/// assertion cannot outlive the process, so the session is the whole truth.
///
/// Expiry is derived here rather than stored, because the expiry timer only
/// samples periodically — a menu opened between two ticks has to work out for
/// itself that the cap has passed instead of offering to turn off a session
/// that already ended.
public enum KeepScreenAwakeState: Equatable, Sendable {
    case off
    case active(remaining: Duration)

    public init(session: KeepAwakeSession?, at instant: ContinuousClock.Instant) {
        guard let session, !session.isExpired(at: instant) else {
            self = .off
            return
        }
        self = .active(remaining: session.remaining(at: instant))
    }
}
