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

    @Test("Clamps a negative remainder rather than rendering a negative countdown")
    func clampsNegativeRemainder() {
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(.seconds(-90)) == "0:00")
    }

    /// The invariant the menu depends on: while a session is genuinely running,
    /// the text can never claim it has run out.
    @Test("Never reads zero for a session with time left", arguments: KeepAwakeDuration.allCases)
    func neverReadsZeroWhileTimeRemains(option: KeepAwakeDuration) {
        let lastMoment = KeepAwakeSession(startedAt: .now, duration: option.duration)
            .remaining(at: .now.advanced(by: option.duration - .seconds(1)))
        #expect(RemainingTimeFormatting.formatHoursAndMinutes(lastMoment) != "0:00")
    }
}
