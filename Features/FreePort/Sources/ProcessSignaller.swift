import Darwin
import WardKit

/// Sends a signal to one process.
///
/// `kill(2)` directly rather than through `BoundedProcess`: spawning `/bin/kill`
/// would add a process that can hang and would flatten `EPERM` and `ESRCH` into
/// one exit status. Those two errors are the whole reason this type exists —
/// "you may not" and "it is already gone" mean opposite things here.
enum ProcessSignaller {
    /// The two signals this feature sends, as a type rather than two `Int32`s.
    /// `send(_:to:)` would otherwise take a signal number and a pid of the same
    /// type, and a transposed call would still compile.
    enum Signal {
        case terminate
        case forceKill

        var number: Int32 {
            switch self {
            case .terminate:
                return SIGTERM
            case .forceKill:
                return SIGKILL
            }
        }
    }

    enum SignalOutcome: Equatable {
        case signalled
        /// The process exited on its own between the listing and the signal.
        /// Expected, and success: the point was for it to be gone.
        case alreadyGone
        case notPermitted
        case failed
    }

    static func send(_ signal: Signal, to processIdentifier: Int32) -> SignalOutcome {
        // kill(2) reads 0 as "every process in my group" and -1 as "every
        // process I own". The parser already refuses such pids; this is the
        // second lock on the one mistake in this codebase that has no undo.
        guard processIdentifier > 0 else {
            WardLogger.freePort.fault(
                "Refused to signal pid \(processIdentifier, privacy: .public) — kill(2) would broadcast it."
            )
            return .failed
        }
        guard kill(processIdentifier, signal.number) != 0 else {
            return .signalled
        }
        switch errno {
        case ESRCH:
            return .alreadyGone
        case EPERM:
            // Should be unreachable: KillEscalation only ever hands over pids
            // owned by this user. If it fires, the ownership check has a hole.
            WardLogger.freePort.fault(
                "Denied permission to signal pid \(processIdentifier, privacy: .public), which Ward believed it owned."
            )
            return .notPermitted
        default:
            WardLogger.freePort.error(
                "kill(\(processIdentifier, privacy: .public)) failed with errno \(errno, privacy: .public)."
            )
            return .failed
        }
    }
}
