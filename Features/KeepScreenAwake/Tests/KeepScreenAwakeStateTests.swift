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

    /// A session that outlives its own cap has not ended — the assertion is
    /// still held, because `stop()` only clears the session once the release
    /// actually succeeds. Reporting `.off` here would darken the bolt and offer
    /// the duration picker while the screen was still being forced awake.
    @Test("Reports overrunning at the cap, not off — the assertion is still held")
    func isOverrunningAtCap() {
        let state = KeepScreenAwakeState(
            session: makeHalfHourSession(),
            at: startInstant.advanced(by: .seconds(1800))
        )
        #expect(state == .overrunning)
    }

    @Test("Stays overrunning well past the cap")
    func isOverrunningPastCap() {
        let state = KeepScreenAwakeState(
            session: makeHalfHourSession(),
            at: startInstant.advanced(by: .seconds(99999))
        )
        #expect(state == .overrunning)
    }

    @Test("Is off only when no session is held at all")
    func isOffOnlyWithoutSession() {
        #expect(KeepScreenAwakeState(session: nil, at: startInstant.advanced(by: .seconds(99999))) == .off)
    }

    @Test("Every offered duration overruns at its own cap", arguments: KeepAwakeDuration.allCases)
    func everyOfferedDurationOverrunsAtItsCap(option: KeepAwakeDuration) {
        let session = KeepAwakeSession(startedAt: startInstant, duration: option.duration)
        let atCap = KeepScreenAwakeState(session: session, at: startInstant.advanced(by: option.duration))
        #expect(atCap == .overrunning)
    }
}
