/// What Ward does about a missing permission, in order, as a state machine with
/// no side effects.
///
/// Both permission flows used to fire the system prompt and then open Ward's own
/// alert, back to back. Two modals arrived at once and the system one — which
/// can only say "Ward" — landed in front of the one naming the exact bundle and
/// warning that a stale entry reads as enabled while granting nothing. On a
/// machine where a `brew install` build and a local `make-app.sh` build coexist,
/// that is the difference between granting the right app and flipping a switch
/// that was already on.
///
/// The ordering lives here rather than in the code holding the AppKit calls, for
/// the same reason `KillEscalation` does: it is the part that can be got wrong,
/// so it is the part that should be testable. What makes the old bug
/// unexpressible is `Stage` — no stage yields `.registerWithSystem` before an
/// explanation has happened, so there is no way to ask for the system prompt
/// first. Adding one would put the bug back.
enum PermissionEscalation {
    enum Stage: Equatable, Sendable {
        /// Nothing has been shown yet. `isAlreadyGranted` is the preflight
        /// answer — the non-prompting check, never the one that shows a dialog.
        case notYetAsked(isAlreadyGranted: Bool)
        /// Ward's alert has been read and dismissed.
        case explained(userChoseSettings: Bool)
    }

    enum Step: Equatable, Sendable {
        /// Ward's own alert, which is the only one that can name the bundle.
        case explain
        /// The system prompt. Kept, and kept before the pane opens, because it
        /// is what puts a row in the list for the user to enable — the dialog it
        /// also shows is the cost of that, not the point of it.
        case registerWithSystem
        case openSettingsPane
    }

    /// Deliberately returns the whole ordered list rather than one step at a
    /// time. Registration and opening the pane are not separated by anything the
    /// caller has to observe in between, and a caller asking twice could be
    /// handed them in either order.
    static func nextSteps(_ stage: Stage) -> [Step] {
        switch stage {
        case .notYetAsked(let isAlreadyGranted):
            return isAlreadyGranted ? [] : [.explain]
        case .explained(let userChoseSettings):
            // Cancelling is a complete answer, not a deferral: nothing is
            // registered and nothing is opened. Ward has already said what to do
            // and the user declined to do it now.
            return userChoseSettings ? [.registerWithSystem, .openSettingsPane] : []
        }
    }
}
