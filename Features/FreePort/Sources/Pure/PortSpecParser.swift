import Foundation

/// Turns what the user typed into a port number.
///
/// This is the only free-text route into an irreversible action, so it accepts
/// the three shapes people actually paste — `3001`, `:3001`, `tcp:3001` — and
/// rejects everything else rather than salvaging a number out of it. A spec
/// like `3001abc` is a typo, and guessing which half was meant is how the wrong
/// process gets killed.
public enum PortSpecParser {
    private static let tcpPrefix = "tcp:"
    private static let bareColonPrefix = ":"

    public static func parse(_ specification: String) -> UInt16? {
        let digits = strippingProtocolPrefix(
            from: specification.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        // Port 0 means "any free port" to bind(2); it is never something to free.
        guard let port = UInt16(digits), port > 0 else {
            return nil
        }
        return port
    }

    private static func strippingProtocolPrefix(from specification: String) -> String {
        if specification.lowercased().hasPrefix(tcpPrefix) {
            return String(specification.dropFirst(tcpPrefix.count))
        }
        if specification.hasPrefix(bareColonPrefix) {
            return String(specification.dropFirst(bareColonPrefix.count))
        }
        return specification
    }
}
