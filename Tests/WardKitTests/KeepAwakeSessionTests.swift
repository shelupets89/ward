import Testing
@testable import WardKit

struct KeepAwakeSessionTests {
    private let startInstant = ContinuousClock.now

    @Test("Is not expired at the moment it starts")
    func isNotExpiredAtStart() {
        let session = KeepAwakeSession(startedAt: startInstant, duration: .seconds(3600))
        #expect(!session.isExpired(at: startInstant))
    }

    @Test("Is not expired one second before the deadline")
    func isNotExpiredJustBeforeDeadline() {
        let session = KeepAwakeSession(startedAt: startInstant, duration: .seconds(3600))
        #expect(!session.isExpired(at: startInstant.advanced(by: .seconds(3599))))
    }

    @Test("Is expired exactly at the deadline")
    func isExpiredAtDeadline() {
        let session = KeepAwakeSession(startedAt: startInstant, duration: .seconds(3600))
        #expect(session.isExpired(at: startInstant.advanced(by: .seconds(3600))))
    }

    @Test("Is expired well past the deadline")
    func isExpiredPastDeadline() {
        let session = KeepAwakeSession(startedAt: startInstant, duration: .seconds(3600))
        #expect(session.isExpired(at: startInstant.advanced(by: .seconds(99999))))
    }

    @Test("Reports the full duration as remaining at the start")
    func reportsFullDurationRemainingAtStart() {
        let session = KeepAwakeSession(startedAt: startInstant, duration: .seconds(3600))
        #expect(session.remaining(at: startInstant) == .seconds(3600))
    }

    @Test("Counts remaining time down as the session runs")
    func countsRemainingDown() {
        let session = KeepAwakeSession(startedAt: startInstant, duration: .seconds(3600))
        #expect(session.remaining(at: startInstant.advanced(by: .seconds(600))) == .seconds(3000))
    }

    @Test("Clamps remaining time to zero rather than going negative")
    func clampsRemainingToZero() {
        let session = KeepAwakeSession(startedAt: startInstant, duration: .seconds(60))
        #expect(session.remaining(at: startInstant.advanced(by: .seconds(600))) == .zero)
    }

    /// The reason this type traps on nothing. A duration that is not positive
    /// is a developer mistake, but it is a *defined* one: the session is born
    /// expired, so the first expiry check restores the setting rather than a
    /// trap stranding it. These pin that, since it is the whole argument for
    /// letting a bad duration through instead of dying on it.
    @Test("Is already expired at its own start when built with a non-positive duration",
          arguments: [Duration.zero, .seconds(-1), .seconds(-99999)])
    func isBornExpiredWhenDurationIsNotPositive(duration: Duration) {
        let session = KeepAwakeSession(startedAt: startInstant, duration: duration)
        #expect(session.isExpired(at: startInstant))
    }

    @Test("Reports nothing remaining when built with a non-positive duration",
          arguments: [Duration.zero, .seconds(-1)])
    func reportsNothingRemainingWhenDurationIsNotPositive(duration: Duration) {
        let session = KeepAwakeSession(startedAt: startInstant, duration: duration)
        #expect(session.remaining(at: startInstant) == .zero)
    }
}

struct KeepAwakeDurationTests {
    @Test("Every offered duration is capped — none runs forever")
    func everyDurationIsFinite() {
        for option in KeepAwakeDuration.allCases {
            #expect(option.duration > .zero)
            #expect(option.duration <= .seconds(8 * 3600))
        }
    }

    @Test(
        "Menu titles describe the span",
        arguments: zip(
            KeepAwakeDuration.allCases,
            ["30 minutes", "2 hours", "8 hours"]
        )
    )
    func menuTitlesDescribeSpan(option: KeepAwakeDuration, expectedTitle: String) {
        #expect(option.menuTitle == expectedTitle)
    }
}
