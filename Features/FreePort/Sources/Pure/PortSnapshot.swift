/// What is known about one port at one instant.
///
/// The two fields answer different questions and neither implies the other:
/// `holders` is what `lsof` could see, which without root is only this user's
/// own processes; `isOccupied` is what `netstat` says, which covers everyone.
/// Empty holders with `isOccupied` true is therefore the normal shape of a
/// root-held port, not a contradiction.
///
/// The opposite disagreement — holders present, `isOccupied` false — is also
/// reachable, because the two commands run one after the other rather than
/// atomically. It needs no handling: `isOccupied` is only ever consulted when
/// `holders` is empty. Seeing a holder is the stronger evidence, so nothing
/// downstream asks `netstat` to confirm it.
public struct PortSnapshot: Equatable, Sendable {
    public let holders: [ListeningProcess]
    public let isOccupied: Bool

    public init(holders: [ListeningProcess], isOccupied: Bool) {
        self.holders = holders
        self.isOccupied = isOccupied
    }
}
