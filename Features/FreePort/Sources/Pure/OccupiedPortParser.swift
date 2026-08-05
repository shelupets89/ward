/// Reads which TCP ports are listening out of `netstat -an -p tcp` output.
///
/// This exists because an unprivileged `lsof` cannot see other users' sockets
/// at all — a root-held port produces no rows and a non-zero exit, exactly like
/// a genuinely free port. Reporting "nothing was listening" about a port that
/// is in use is the one answer that sends the user back to try again, so
/// occupancy is read from `netstat`, which needs no privileges and lists every
/// listener regardless of owner.
///
/// It answers *whether* a port is taken, never *by whom*: the owner is only
/// ever learned from `lsof`, and only for processes this user could signal.
public enum OccupiedPortParser {
    private static let listenStateMarker = "LISTEN"
    private static let localAddressFieldIndex = 3

    public static func isPortOccupied(_ port: UInt16, in netstatOutput: String) -> Bool {
        return listeningPorts(in: netstatOutput).contains(port)
    }

    public static func listeningPorts(in netstatOutput: String) -> Set<UInt16> {
        return Set(netstatOutput.split(separator: "\n").compactMap(parseListeningPort(fromRow:)))
    }

    private static func parseListeningPort(fromRow row: Substring) -> UInt16? {
        let fields = row.split(whereSeparator: \.isWhitespace)
        // The state is the last field, so this rejects the banner, the header
        // and every non-listening connection in one test.
        guard fields.count > localAddressFieldIndex,
              let state = fields.last,
              state == listenStateMarker else {
            return nil
        }
        return parsePort(fromAddress: fields[localAddressFieldIndex])
    }

    /// `netstat` separates the port with a dot rather than a colon, so an IPv6
    /// address stays unambiguous: `*.3000`, `127.0.0.1.61062`, `::1.9229`.
    private static func parsePort(fromAddress address: Substring) -> UInt16? {
        guard let portField = address.split(separator: ".").last,
              let port = UInt16(portField),
              port > 0 else {
            return nil
        }
        return port
    }
}
