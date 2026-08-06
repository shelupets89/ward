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
        case .freedThenTakenByAnotherUser:
            return AlertText(
                title: "Port \(port) is in use again",
                body: """
                Ward stopped what you approved. Port \(port) is already in use again, by a \
                process you do not own — and without administrator rights Ward cannot see \
                which one. Nothing you approved is still running.
                """
            )
        case .stillHeld(let signalled, let undelivered):
            return stillHeldPort(port, signalled: signalled, undelivered: undelivered)
        case .heldByAnotherUser(let visibleHolders):
            return anotherUsersPort(port, visibleHolders: visibleHolders)
        case .takenByAnotherProcess(let holders):
            return AlertText(
                title: "Port \(port) is in use again",
                body: """
                What you approved is gone, but port \(port) is now held by:

                \(list(holders))
                Ward did not signal \(holders.count == 1 ? "it" : "them") — \
                \(holders.count == 1 ? "it was" : "they were") not in the list you approved. \
                Something is probably restarting the server. Try again to stop what is there now.
                """
            )
        }
    }

    /// Both lists are rendered when both are non-empty. Reporting only one of
    /// them would leave a process holding the port unnamed, which is the same
    /// failure as reporting a count instead of names.
    private static func stillHeldPort(
        _ port: UInt16,
        signalled: [ListeningProcess],
        undelivered: [ListeningProcess]
    ) -> AlertText {
        let survivedParagraph = signalled.isEmpty ? "" : """


        \(signalled.count == 1 ? "This survived" : "These survived") both SIGTERM and SIGKILL:

        \(list(signalled))
        """
        let undeliveredParagraph = undelivered.isEmpty ? "" : """


        Ward could not deliver a signal to \(undelivered.count == 1 ? "this one" : "these"), so \
        \(undelivered.count == 1 ? "it was" : "they were") never sent anything. That usually \
        means the process is protected by the system, and stopping it from a terminal will \
        not work either:

        \(list(undelivered))
        """
        return AlertText(
            title: "Port \(port) is still in use",
            body: "Port \(port) is still held.\(survivedParagraph)\(undeliveredParagraph)"
        )
    }

    /// Branches on emptiness inside one case rather than across two `where`
    /// clauses: an "unknown holder" reported as an empty list of known holders
    /// is a message with a heading and nothing under it.
    private static func anotherUsersPort(
        _ port: UInt16,
        visibleHolders: [ListeningProcess]
    ) -> AlertText {
        guard !visibleHolders.isEmpty else {
            return AlertText(
                title: "Port \(port) belongs to another user",
                body: """
                Something is listening on port \(port), but it is not one of your processes. \
                Ward only ever stops processes you own, and without administrator rights it \
                cannot see which process this is. Free it from a terminal if you are sure.
                """
            )
        }
        return AlertText(
            title: "Port \(port) belongs to another user",
            body: """
            Port \(port) is held by:

            \(list(visibleHolders))
            Ward only ever stops processes you own, so nothing was signalled.
            """
        )
    }

    /// Only for a read that failed *before* anything was signalled. Once a
    /// signal has gone out, "nothing was changed" is no longer true — use
    /// `unverifiablePort` instead.
    public static func unreadablePort(_ port: UInt16) -> AlertText {
        return AlertText(
            title: "Ward couldn’t check port \(port)",
            body: """
            Reading which processes hold port \(port) failed, so nothing was stopped. \
            Nothing on this Mac was changed.
            """
        )
    }

    public static func unverifiablePort(_ port: UInt16) -> AlertText {
        return AlertText(
            title: "Ward couldn’t confirm port \(port)",
            body: """
            Ward already signalled the processes you approved, but then failed to re-read \
            port \(port) — so it cannot say whether they stopped. Assume they may have. \
            Check the port before starting anything on it.
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
