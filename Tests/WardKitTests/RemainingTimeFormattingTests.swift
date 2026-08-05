import Testing
@testable import WardKit

struct RemainingTimeFormattingTests {
    @Test(
        "Rounds up, so any time left reads as at least a minute",
        arguments: zip(
            [Duration.seconds(1), .seconds(29), .seconds(59), .seconds(60), .milliseconds(500)],
            ["0:01", "0:01", "0:01", "0:01", "0:01"]
        )
    )
    func roundsUpToWholeMinutes(remaining: Duration, expectedText: String) {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(remaining) == expectedText)
    }

    @Test("Moves to the next minute as soon as one is exceeded")
    func movesToNextMinuteWhenExceeded() {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(.seconds(61)) == "0:02")
    }

    @Test(
        "Counts a session down",
        arguments: zip(
            [Duration.seconds(1800), .seconds(1799), .seconds(1740), .seconds(600)],
            ["0:30", "0:30", "0:29", "0:10"]
        )
    )
    func countsDown(remaining: Duration, expectedText: String) {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(remaining) == expectedText)
    }

    @Test("Pads the minute component to two digits past the hour")
    func padsMinutesPastTheHour() {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(.seconds(3660)) == "1:01")
    }

    @Test(
        "Rolls into hours without over-rounding at the boundary",
        arguments: zip(
            [Duration.seconds(3599), .seconds(3600), .seconds(3601), .seconds(9420), .seconds(36000)],
            ["1:00", "1:00", "1:01", "2:37", "10:00"]
        )
    )
    func rollsIntoHours(remaining: Duration, expectedText: String) {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(remaining) == expectedText)
    }

    /// `.seconds(Int64.max)` is unreachable through `KeepAwakeDuration`, but the
    /// function is public and takes any `Duration` — and a ceiling computed as
    /// `seconds + 59` overflows here, which traps rather than returning.
    @Test("Survives a duration large enough to overflow the ceiling arithmetic")
    func survivesAnEnormousDuration() {
        #expect(!RemainingTimeFormatting.formatHoursAndMinutes(.seconds(Int64.max)).isEmpty)
    }

    @Test(
        "Renders each offered duration at full length",
        arguments: zip(KeepAwakeDuration.allCases, ["0:30", "2:00", "8:00"])
    )
    func rendersEachOfferedDuration(option: KeepAwakeDuration, expectedText: String) {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(option.duration) == expectedText)
    }

    @Test("Reads zero only when nothing is left")
    func readsZeroWhenNothingIsLeft() {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(.zero) == "0:00")
    }

    /// These magnitudes are chosen, not arbitrary: −90s happens to render "0:00"
    /// through the unguarded arithmetic too, so it would pass with the clamp
    /// deleted. −120s and −3700s produce "0:0-1" and "-1:00" without it.
    @Test(
        "Clamps a negative remainder rather than rendering a negative countdown",
        arguments: [Duration.seconds(-120), .seconds(-3700), .milliseconds(-1)]
    )
    func clampsNegativeRemainder(remaining: Duration) {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(remaining) == "0:00")
    }

    /// Asserts the exact text rather than "not 0:00": a stub returning anything
    /// non-empty would satisfy the negative form, which is how the original bug
    /// would have slipped past this very test.
    @Test("Reads one minute at the last second of a session", arguments: KeepAwakeDuration.allCases)
    func readsOneMinuteAtTheLastSecond(option: KeepAwakeDuration) {
        let lastMoment = KeepAwakeSession(startedAt: .now, duration: option.duration)
            .remaining(at: .now.advanced(by: option.duration - .seconds(1)))
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(lastMoment) == "0:01")
    }
}
