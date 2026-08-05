/// Countdown text for a menu title, as `H:MM`.
///
/// Deliberately not `Duration.formatted(.time(pattern: .hourMinute))`, which
/// rounds to the *nearest* minute: that rendered "0:00 left" for the last half
/// minute of every session, while the assertion was still held. Rounding up
/// instead means a running session can never claim it has run out.
///
/// Hand-formatted rather than localised on purpose. A `Pure/` function has to
/// be a function of its inputs alone, and a locale-aware formatter would make
/// this one depend on ambient state and produce non-ASCII digits in some
/// regions — untestable in exactly the way this file exists to avoid.
public enum RemainingTimeFormatting {
    public static func formatHoursAndMinutes(_ remaining: Duration) -> String {
        guard remaining > .zero else {
            return "0:00"
        }
        let (seconds, attoseconds) = remaining.components
        // Divide before rounding up. The usual `(seconds + 59) / 60` ceiling
        // overflows Int64 near `.seconds(Int64.max)`, and Swift traps on that
        // rather than returning — a crash in a formatter nothing validates.
        let wholeMinutes = seconds / 60
        let hasPartialMinute = seconds % 60 > 0 || attoseconds > 0
        let minutesRoundedUp = hasPartialMinute ? wholeMinutes + 1 : wholeMinutes
        let minutePart = minutesRoundedUp % 60
        let paddedMinutes = minutePart < 10 ? "0\(minutePart)" : "\(minutePart)"
        return "\(minutesRoundedUp / 60):\(paddedMinutes)"
    }
}
