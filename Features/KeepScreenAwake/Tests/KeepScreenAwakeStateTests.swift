import Testing
import WardKit
@testable import KeepScreenAwake

/// The menu is rebuilt from this state on every open, so these cases are the
/// whole contract between a running session and what the user is offered.
struct KeepScreenAwakeStateTests {
    private let startInstant = ContinuousClock.now

    private func makeHalfHourSession() -> KeepAwakeSession {
        return KeepAwakeSession(startedAt: startInstant, duration: .seconds(1800))
    }

    @Test("Is off when no session is running")
    func isOffWithoutSession() {
        #expect(KeepScreenAwakeState(session: nil, at: startInstant) == .off)
    }

    @Test("Reports the full duration as remaining the moment a session starts")
    func isActiveAtStart() {
        let state = KeepScreenAwakeState(session: makeHalfHourSession(), at: startInstant)
        #expect(state == .active(remaining: .seconds(1800)))
    }

    @Test("Counts the remaining time down while the session runs")
    func countsRemainingDown() {
        let state = KeepScreenAwakeState(
            session: makeHalfHourSession(),
            at: startInstant.advanced(by: .seconds(600))
        )
        #expect(state == .active(remaining: .seconds(1200)))
    }

    @Test("Is still active one second before the cap")
    func isActiveJustBeforeCap() {
        let state = KeepScreenAwakeState(
            session: makeHalfHourSession(),
            at: startInstant.advanced(by: .seconds(1799))
        )
        #expect(state == .active(remaining: .seconds(1)))
    }

    @Test("Falls back to off exactly at the cap, without waiting for a sweep")
    func isOffAtCap() {
        let state = KeepScreenAwakeState(
            session: makeHalfHourSession(),
            at: startInstant.advanced(by: .seconds(1800))
        )
        #expect(state == .off)
    }

    @Test("Stays off well past the cap rather than reporting zero remaining")
    func isOffPastCap() {
        let state = KeepScreenAwakeState(
            session: makeHalfHourSession(),
            at: startInstant.advanced(by: .seconds(99999))
        )
        #expect(state == .off)
    }

    @Test("Every offered duration ends the session at its own cap", arguments: KeepAwakeDuration.allCases)
    func everyOfferedDurationEndsAtItsCap(option: KeepAwakeDuration) {
        let session = KeepAwakeSession(startedAt: startInstant, duration: option.duration)
        #expect(KeepScreenAwakeState(session: session, at: startInstant.advanced(by: option.duration)) == .off)
    }
}
