/// What is known about one port at one instant.
///
/// The two fields answer different questions and neither implies the other:
/// `holders` is what `lsof` could see, which without root is only this user's
/// own processes; `isOccupied` is what `netstat` says, which covers everyone.
/// Empty holders with `isOccupied` true is therefore the normal shape of a
/// root-held port, not a contradiction.
public struct PortSnapshot: Equatable, Sendable {
    public let holders: [ListeningProcess]
    public let isOccupied: Bool

    public init(holders: [ListeningProcess], isOccupied: Bool) {
        self.holders = holders
        self.isOccupied = isOccupied
    }
}
