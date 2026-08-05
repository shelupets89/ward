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
        guard let isOccupied = isPortOccupied(port) else {
            return nil
        }
        return PortSnapshot(holders: holders(ofPort: port), isOccupied: isOccupied)
    }

    static func allListeningProcesses() -> [ListeningProcess] {
        return parseListeners(matching: "-iTCP")
    }

    private static func holders(ofPort port: UInt16) -> [ListeningProcess] {
        return parseListeners(matching: "-iTCP:\(port)")
    }

    /// A non-zero exit is how `lsof` says "nothing matched", so the exit status
    /// is ignored and the absence of parsable rows is the answer.
    private static func parseListeners(matching networkFilter: String) -> [ListeningProcess] {
        let outcome = BoundedProcess.run(
            executablePath: lsofPath,
            arguments: lsofListenerArguments + [networkFilter],
            capturesOutput: true
        )
        return ListeningProcessParser.parse(outcome.standardOutput)
    }

    private static func isPortOccupied(_ port: UInt16) -> Bool? {
        let outcome = BoundedProcess.run(
            executablePath: netstatPath,
            arguments: ["-an", "-p", "tcp"],
            capturesOutput: true
        )
        // netstat always has something to say, so silence means it never ran.
        guard outcome.didSucceed, !outcome.standardOutput.isEmpty else {
            WardLogger.freePort.error("netstat gave no output; port occupancy is unknown.")
            return nil
        }
        return OccupiedPortParser.isPortOccupied(port, in: outcome.standardOutput)
    }
}
