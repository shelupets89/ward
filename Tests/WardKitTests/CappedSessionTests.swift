import Foundation
import Testing
@testable import WardKit

/// The ordering inside `end(by:)` is the one bug this repo has documented as
/// having actually shipped: the expiry check was disarmed before the privileged
/// restore that ends the session, so a restore the user declined stranded the
/// session with its safety net dead.
///
/// These cases fail if those two steps are ever swapped back. They are not a
/// test of the decision "should we keep retrying?" — that decision would still
/// read correctly in the broken code — but of the order the steps happen in.
///
/// Isolated to the main actor because `CappedSession` is: its expiry check is a
/// `Timer` on `RunLoop.main`.
@MainActor
struct CappedSessionTests {
    /// Long enough that the check cannot fire during a test. These cases assert
    /// on whether it is *armed*, never on it ticking, and a tick landing
    /// mid-test would only make them nondeterministic.
    private static let neverFiresWithinATest: TimeInterval = 3600

    private func makeSession(onExpiry: @escaping @MainActor () -> Void = {}) -> CappedSession {
        return CappedSession(expiryCheckInterval: Self.neverFiresWithinATest, onExpiry: onExpiry)
    }

    private func makeHalfHour() -> KeepAwakeSession {
        return KeepAwakeSession(startedAt: .now, duration: .seconds(1800))
    }

    @Test("Arms the expiry check as soon as a session begins")
    func armsTheCheckOnBegin() {
        let session = makeSession()
        session.begin(makeHalfHour())
        #expect(session.isExpiryCheckScheduled)
        #expect(session.current != nil)
    }

    /// The regression test. Swap the two steps in `end(by:)` and this is the
    /// case that goes red.
    @Test("Leaves the expiry check armed when the work that ends the session fails")
    func keepsTheCheckArmedWhenEndingFails() {
        let session = makeSession()
        session.begin(makeHalfHour())

        let didEnd = session.end { false }

        #expect(didEnd == false)
        #expect(session.isExpiryCheckScheduled, "a failed end must leave the session something to retry it")
    }

    @Test("Keeps the session when the work that ends it fails")
    func keepsTheSessionWhenEndingFails() {
        let session = makeSession()
        let started = makeHalfHour()
        session.begin(started)

        session.end { false }

        #expect(session.current == started)
    }

    /// The point of leaving the check armed: the next tick gets another go, and
    /// the one that succeeds ends the session for real.
    @Test("Ends the session on a later attempt that succeeds")
    func endsOnARetryThatSucceeds() {
        let session = makeSession()
        session.begin(makeHalfHour())
        session.end { false }

        let didEnd = session.end { true }

        #expect(didEnd)
        #expect(session.current == nil)
        #expect(session.isExpiryCheckScheduled == false)
    }

    @Test("Disarms the expiry check once the work that ends the session succeeds")
    func disarmsTheCheckWhenEndingSucceeds() {
        let session = makeSession()
        session.begin(makeHalfHour())

        let didEnd = session.end { true }

        #expect(didEnd)
        #expect(session.current == nil)
        #expect(session.isExpiryCheckScheduled == false)
    }

    /// An owner that has nothing running must not be made to release something
    /// it never took — for Keep Screen Awake that would drop an assertion
    /// belonging to another feature.
    @Test("Never runs the ending work when no session is running")
    func doesNotRunTheEndingWorkWithoutASession() {
        let session = makeSession()
        var didRunEndingWork = false

        let didEnd = session.end {
            didRunEndingWork = true
            return true
        }

        #expect(didEnd)
        #expect(didRunEndingWork == false)
        #expect(session.isExpiryCheckScheduled == false)
    }

    @Test("Reports the session it was given, for as long as it is running")
    func reportsTheRunningSession() {
        let session = makeSession()
        let started = makeHalfHour()

        #expect(session.current == nil)
        session.begin(started)
        #expect(session.current == started)
    }
}
