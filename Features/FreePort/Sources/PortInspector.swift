import Foundation
import WardKit

/// Reads the state of a port from the system. Reads only — nothing here signals
/// anything, and neither command needs privileges.
enum PortInspector {
    private static let lsofPath = "/usr/sbin/lsof"
    private static let netstatPath = "/usr/sbin/netstat"
    /// `-l` prints numeric UIDs instead of login names, so ownership is decided
    /// by an exact match against `getuid()` rather than by a name that `lsof`
    /// may have formatted or truncated.
    private static let lsofListenerArguments = ["-l", "-n", "-P", "-sTCP:LISTEN"]

    static var currentUser: String {
        return String(getuid())
    }

    /// `nil` when occupancy could not be established. That is deliberately not
    /// folded into "nothing is listening": the caller is about to tell the user
    /// something definite about a port, and a failed check is not an answer.
    static func snapshot(ofPort port: UInt16) -> PortSnapshot? {
        guard let isOccupied = isPortOccupied(port),
              let holders = parseListeners(matching: "-iTCP:\(port)") else {
            return nil
        }
        return PortSnapshot(holders: holders, isOccupied: isOccupied)
    }

    static func allListeningProcesses() -> [ListeningProcess]? {
        return parseListeners(matching: "-iTCP")
    }

    /// `nil` only when `lsof` never ran. A non-zero exit from a run that
    /// completed is how `lsof` says "nothing matched" — that is an empty list,
    /// not a failure, and the two must not collapse into each other. Treating a
    /// failed check as an empty one would report a port the user owns as
    /// belonging to somebody else.
    private static func parseListeners(matching networkFilter: String) -> [ListeningProcess]? {
        let outcome = BoundedProcess.run(
            executablePath: lsofPath,
            arguments: lsofListenerArguments + [networkFilter],
            capturesOutput: true,
            logger: WardLogger.freePort
        )
        guard outcome.didRun else {
            WardLogger.freePort.error("lsof did not run for \(networkFilter, privacy: .public).")
            return nil
        }
        return ListeningProcessParser.parse(outcome.standardOutput)
    }

    private static func isPortOccupied(_ port: UInt16) -> Bool? {
        let outcome = BoundedProcess.run(
            executablePath: netstatPath,
            arguments: ["-an", "-p", "tcp"],
            capturesOutput: true,
            logger: WardLogger.freePort
        )
        // netstat always has something to say, so silence means it never ran.
        guard outcome.didRun, outcome.didSucceed, !outcome.standardOutput.isEmpty else {
            WardLogger.freePort.error("netstat gave no output; port occupancy is unknown.")
            return nil
        }
        return OccupiedPortParser.isPortOccupied(port, in: outcome.standardOutput)
    }
}
