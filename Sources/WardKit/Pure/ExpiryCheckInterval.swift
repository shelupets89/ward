import Foundation

/// How often a capped session re-asks whether it has expired.
///
/// `Timer` does not read a non-positive interval as "never fire" — it coerces
/// it to a fraction of a millisecond and spins, measured at roughly 7,500 ticks
/// a second. On the lid-closed feature every tick past expiry spawns a `pmset`
/// subprocess, so an interval that is merely wrong becomes an unresponsive Mac.
///
/// Neither a trap nor an assert catches that where it matters: `precondition`
/// fires in release too, where owners build their session during launch — ahead
/// of the leak check — so on a Mac still carrying a setting a crash left behind,
/// it would kill the only thing that would offer to clear it. And `assert` is
/// stripped from exactly the builds that ship, including the `.app` this repo
/// says to launch instead of `swift run`. So the floor is applied rather than
/// asserted, and the assert is left as the developer-time signal on top of it.
public enum ExpiryCheckInterval {
    /// A session cap is measured in minutes at least, so re-asking more than
    /// once a second buys nothing and costs a wakeup.
    public static let shortest: TimeInterval = 1

    public static func clamped(_ requested: TimeInterval) -> TimeInterval {
        return max(requested, shortest)
    }
}
