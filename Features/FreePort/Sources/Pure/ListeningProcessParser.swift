import Foundation

/// Reads `lsof -iTCP -sTCP:LISTEN -P -n` output into processes.
///
/// Every rejection here is deliberate. A row this parser cannot read in full is
/// dropped rather than partially believed: the output feeds a kill list, and a
/// half-understood row is a process the user was never shown. `lsof` also
/// prefixes warnings and a header to real rows, so "unreadable" is the normal
/// case rather than an exceptional one — nothing throws.
public enum ListeningProcessParser {
    private static let listenStateMarker = "(LISTEN)"
    private static let hexEscapePrefix = "\\x"
    private static let commandFieldIndex = 0
    private static let processIdentifierFieldIndex = 1
    private static let userFieldIndex = 2
    private static let addressFieldIndex = 8

    public static func parse(_ lsofOutput: String) -> [ListeningProcess] {
        let rows = lsofOutput.split(separator: "\n").compactMap(makeProcess(fromRow:))
        var alreadySeen = Set<ListeningProcess>()
        return rows.filter { alreadySeen.insert($0).inserted }
    }

    private static func makeProcess(fromRow row: Substring) -> ListeningProcess? {
        let fields = row.split(whereSeparator: \.isWhitespace)
        // `-sTCP:LISTEN` means every row should already be a listener, and the
        // state is the last column. Requiring it *present* rather than merely
        // not-contradictory is the point: a truncated row that stops before the
        // state must not inherit "listening" by omission and reach the kill list.
        guard fields.count > addressFieldIndex,
              let state = fields.last,
              state == listenStateMarker else {
            return nil
        }
        // The header row fails here on "PID", which is why it needs no special case.
        // A non-positive pid is rejected outright: kill(2) reads 0 as "my whole
        // process group" and -1 as "every process I own".
        guard let processIdentifier = Int32(fields[processIdentifierFieldIndex]), processIdentifier > 0 else {
            return nil
        }
        guard let port = parsePort(fromAddress: fields[addressFieldIndex]) else {
            return nil
        }
        return ListeningProcess(
            command: decodingHexEscapes(in: fields[commandFieldIndex]),
            processIdentifier: processIdentifier,
            user: String(fields[userFieldIndex]),
            port: port
        )
    }

    /// The address is `*:3001`, `127.0.0.1:3001` or `[::1]:3001`, so the port is
    /// whatever follows the final colon.
    private static func parsePort(fromAddress address: Substring) -> UInt16? {
        guard let portField = address.split(separator: ":").last,
              let port = UInt16(portField),
              port > 0 else {
            return nil
        }
        return port
    }

    /// `lsof` escapes non-printable bytes in the command name, so "Code H"
    /// arrives as `Code\x20H`. The dialog asking permission to kill it should
    /// say the name the user recognises.
    private static func decodingHexEscapes(in command: Substring) -> String {
        let segments = command.components(separatedBy: hexEscapePrefix)
        guard segments.count > 1 else {
            return String(command)
        }
        return segments.dropFirst().reduce(segments[0]) { decoded, segment in
            guard let byte = UInt8(segment.prefix(2), radix: 16) else {
                return decoded + hexEscapePrefix + segment
            }
            return decoded + String(Character(Unicode.Scalar(byte))) + segment.dropFirst(2)
        }
    }
}
