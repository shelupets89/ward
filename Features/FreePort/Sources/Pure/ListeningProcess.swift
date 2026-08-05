/// One process holding one TCP port.
///
/// `Hashable` is load-bearing rather than incidental: `lsof` prints a row per
/// socket, so a process listening on both IPv4 and IPv6 appears twice with
/// every field identical. Deduplication is set membership on the whole value.
public struct ListeningProcess: Equatable, Hashable, Sendable {
    public let command: String
    public let processIdentifier: Int32
    public let user: String
    public let port: UInt16

    public init(command: String, processIdentifier: Int32, user: String, port: UInt16) {
        self.command = command
        self.processIdentifier = processIdentifier
        self.user = user
        self.port = port
    }

    /// How the process is named in the confirmation dialog. Always the command
    /// and the pid — a count would tell the user nothing about what they are
    /// about to lose, and nothing here can be undone afterwards.
    public var displayName: String {
        return "\(command) (pid \(processIdentifier))"
    }
}
