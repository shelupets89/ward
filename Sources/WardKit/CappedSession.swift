import Foundation

/// A time-capped session together with the repeating check that ends it.
///
/// The two live in one type because the order they are torn down in is a safety
/// property, and holding them apart is what let it go wrong once: an earlier
/// `KeepAwakeController` stopped its expiry timer before the privileged restore
/// that ends the session, so a restore the user declined left the session
/// running with nothing left to retry it. For a feature that flips a setting
/// outliving the process, that is a Mac left unable to sleep and no safety net
/// still running that would ever fix it.
///
/// So `end(by:)` is handed the work that ends the session rather than being told
/// how it went: the check is disarmed on the far side of that work succeeding,
/// and an owner has no timer of its own to disarm early.
///
/// `onExpiry` is retained for the timer's lifetime, so an owner that stores a
/// `CappedSession` must capture itself weakly in the closure.
@MainActor
public final class CappedSession {
    private let expiryTimer: ExpiryTimer
    public private(set) var current: KeepAwakeSession?

    public init(expiryCheckInterval: TimeInterval, onExpiry: @escaping @MainActor () -> Void) {
        // The floor is what actually holds in a shipped build; see
        // `ExpiryCheckInterval`. This is the developer-time signal on top of it.
        assert(expiryCheckInterval > 0, "expiryCheckInterval must be positive")
        expiryTimer = ExpiryTimer(
            interval: ExpiryCheckInterval.clamped(expiryCheckInterval),
            onTick: onExpiry
        )
    }

    /// Whether the expiry check is still armed. A running session while this is
    /// false is precisely the stranded state this type exists to prevent, and
    /// asserting on it is how the tests hold that ordering in place.
    var isExpiryCheckScheduled: Bool {
        return expiryTimer.isScheduled
    }

    /// Starts a session and arms the check that will end it, reporting whether
    /// it did.
    ///
    /// A session already running is kept rather than replaced — replacing would
    /// restart the cap from now, and for one of the two features this backs the
    /// cap is a safety feature rather than a convenience, so refusing has to be
    /// the shared default. The result exists so a caller that lost is told so,
    /// rather than announcing a start that never happened.
    ///
    /// Deliberately not a `precondition`: this runs after the caller has already
    /// changed system state, so trapping would strand exactly what this type
    /// exists to bound.
    public func begin(_ session: KeepAwakeSession) -> Bool {
        guard current == nil else {
            return false
        }
        current = session
        expiryTimer.start()
        return true
    }

    /// Ends the session by running `finish`, and disarms the expiry check only
    /// once that has succeeded. A `finish` that fails leaves both the session
    /// and the check exactly as they were, so the next tick tries again — a
    /// restore that has already failed once is when the retry matters most.
    ///
    /// Returns false only when `finish` did. `finish` is not run at all when
    /// there is no session, so an owner cannot release something it never took.
    public func end(by finish: () -> Bool) -> Bool {
        guard current != nil else {
            return true
        }
        guard finish() else {
            return false
        }
        expiryTimer.stop()
        current = nil
        return true
    }
}
