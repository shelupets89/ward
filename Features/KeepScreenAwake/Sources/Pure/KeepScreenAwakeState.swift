import WardKit

/// What the Keep Screen Awake menu should show, derived from the session alone.
///
/// Unlike its lid-closed namesake there is no system setting to consult: the
/// assertion cannot outlive the process, so the session is the whole truth.
///
/// A session exists for exactly as long as the assertion is held: the
/// controller clears it only once the release actually succeeds. So `.off`
/// means "nothing held", and the cap passing does **not** mean the same thing
/// — a release the OS refuses leaves a session alive past its own deadline.
/// That is `.overrunning`, and collapsing it into `.off` would darken the
/// menu-bar bolt and offer to start a fresh session while the screen was still
/// being forced awake.
public enum KeepScreenAwakeState: Equatable, Sendable {
    case off
    case active(remaining: Duration)
    case overrunning

    public init(session: KeepAwakeSession?, at instant: ContinuousClock.Instant) {
        guard let session else {
            self = .off
            return
        }
        guard !session.isExpired(at: instant) else {
            self = .overrunning
            return
        }
        self = .active(remaining: session.remaining(at: instant))
    }
}
