import Darwin
import Testing
@testable import FreePort

/// `ProcessSignaller` is glue and the repo does not gate glue on coverage — but
/// the pid guard is the second of two locks on the only mistake in this
/// codebase with no undo, and it was the one lock with nothing holding it in
/// place. These cases never reach `kill(2)`: the guard returns first, which is
/// precisely what they assert.
struct ProcessSignallerTests {
    @Test(
        "Refuses the pids kill(2) reads as a broadcast rather than as a process",
        arguments: [Int32(0), -1, -1000, Int32.min]
    )
    func refusesBroadcastIdentifiers(processIdentifier: Int32) {
        #expect(ProcessSignaller.send(.terminate, to: processIdentifier) == .failed)
        #expect(ProcessSignaller.send(.forceKill, to: processIdentifier) == .failed)
    }

    // There is deliberately no test for the ESRCH ("already gone") path. Naming
    // a supposedly-dead pid means sending a real SIGTERM to whatever the kernel
    // has there now, and macOS recycles pids by cumulative process count — on a
    // Mac with any uptime, a "safely high" constant is live sooner or later.
    // A test suite for the one feature that can lose the user's work must not
    // be able to kill one of their processes.

    @Test("Maps its two signals to the numbers kill(2) expects")
    func mapsSignalsToNumbers() {
        #expect(ProcessSignaller.Signal.terminate.number == SIGTERM)
        #expect(ProcessSignaller.Signal.forceKill.number == SIGKILL)
    }
}
