/// Every sentence this feature shows the user.
///
/// This is `Pure/` on purpose. The confirmation dialog is the entire safety
/// mechanism — once the user presses the button nothing can be undone — so what
/// it says is a tested property, not incidental copy. In particular it always
/// lists processes by name and pid: a count tells the user nothing about what
/// they are about to lose.
public enum FreePortMessages {
    public struct AlertText: Equatable, Sendable {
        public let title: String
        public let body: String

        public init(title: String, body: String) {
            self.title = title
            self.body = body
        }
    }

    public static func confirmation(
        port: UInt16,
        targets: [ListeningProcess],
        leftAlone: [ListeningProcess]
    ) -> AlertText {
        let subject = targets.count == 1 ? "that process" : "those processes"
        return AlertText(
            title: "Free port \(port)?",
            body: """
            Ward will stop:

            \(list(targets))
            \(leftAloneParagraph(leftAlone))This cannot be undone. Anything unsaved in \(subject) is lost.
            """
        )
    }

    public static func outcome(_ outcome: KillEscalation.Outcome, port: UInt16) -> AlertText {
        switch outcome {
        case .freed:
            return AlertText(
                title: "Port \(port) is free",
                body: "Nothing is listening on port \(port) any more."
            )
        case .nothingWasListening:
            return AlertText(
                title: "Nothing is using port \(port)",
                body: "No process is listening on port \(port), so there was nothing to stop."
            )
        case .heldByAnotherUser(let visibleHolders) where visibleHolders.isEmpty:
            return AlertText(
                title: "Port \(port) belongs to another user",
                body: """
                Something is listening on port \(port), but it is not one of your processes. \
                Ward only ever stops processes you own, and without administrator rights it \
                cannot see which process this is. Free it from a terminal if you are sure.
                """
            )
        case .heldByAnotherUser(let visibleHolders):
            return AlertText(
                title: "Port \(port) belongs to another user",
                body: """
                Port \(port) is held by:

                \(list(visibleHolders))
                Ward only ever stops processes you own, so nothing was signalled.
                """
            )
        case .stillHeld(let holders):
            return AlertText(
                title: "Port \(port) is still in use",
                body: """
                Port \(port) is still held by:

                \(list(holders))
                It survived both SIGTERM and SIGKILL.
                """
            )
        }
    }

    public static func unreadablePort(_ port: UInt16) -> AlertText {
        return AlertText(
            title: "Ward couldn’t check port \(port)",
            body: """
            Reading which processes hold port \(port) failed, so nothing was stopped. \
            Nothing on this Mac was changed.
            """
        )
    }

    public static func unreadablePortSpecification(_ specification: String) -> AlertText {
        return AlertText(
            title: "“\(specification)” is not a port",
            body: "Enter a TCP port between 1 and 65535, optionally written as :3001 or tcp:3001."
        )
    }

    private static func list(_ processes: [ListeningProcess]) -> String {
        return processes
            .map { "    \($0.displayName)" }
            .joined(separator: "\n")
    }

    private static func leftAloneParagraph(_ leftAlone: [ListeningProcess]) -> String {
        guard !leftAlone.isEmpty else {
            return "\n"
        }
        return """


        Left alone, because you do not own it:

        \(list(leftAlone))

        """
    }
}
