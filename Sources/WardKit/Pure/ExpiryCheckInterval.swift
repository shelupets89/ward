import Foundation

/// How often a capped session re-asks whether it has expired.
///
/// There is a floor because `Timer` does not read a non-positive interval as
/// "never fire" — it coerces it to a fraction of a millisecond and spins, and
/// every tick past expiry attempts a privileged restore.
///
/// It is applied rather than checked because neither kind of check reaches
/// where it matters. `precondition` also fires in release, where owners build
/// their session during launch, ahead of the leak check — so on a Mac still
/// carrying a setting a crash left behind, it would kill the only thing that
/// would offer to clear it. And `assert` is stripped from the builds that ship.
public enum ExpiryCheckInterval {
    /// Every cap the menu offers is half an hour or more, so re-asking more
    /// often than this buys nothing.
    public static let shortest: TimeInterval = 1

    /// Non-finite intervals are held to the floor rather than passed on, and
    /// `max` alone cannot do it: every comparison against `nan` is false, so
    /// `nan` would come straight back out.
    public static func clamped(_ requested: TimeInterval) -> TimeInterval {
        guard requested.isFinite else {
            return shortest
        }
        return max(requested, shortest)
    }
}
