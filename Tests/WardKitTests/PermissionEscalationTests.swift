import Testing
@testable import WardKit

/// The ordering these cases hold is the one that shipped: the system prompt
/// fired before Ward's alert, so two modals arrived together and the one that
/// could name the bundle was behind the one that could not.
///
/// They assert exact arrays, never membership. Every wrong order contains the
/// right steps, so `contains` would pass against all of them — which is the way
/// an ordering test stops testing the ordering.
struct PermissionEscalationTests {
    @Test("Asks for nothing when the permission is already granted")
    func silentWhenAlreadyGranted() {
        #expect(PermissionEscalation.nextSteps(.notYetAsked(isAlreadyGranted: true)) == [])
    }

    /// The regression case. A machine that put `.registerWithSystem` here is
    /// exactly what the old code did.
    @Test("Explains, and only explains, before the user has answered")
    func explainsFirstWhenNotGranted() {
        #expect(PermissionEscalation.nextSteps(.notYetAsked(isAlreadyGranted: false)) == [.explain])
    }

    @Test("Registers nothing and opens nothing when the user cancels")
    func cancellingFiresNothing() {
        #expect(PermissionEscalation.nextSteps(.explained(userChoseSettings: false)) == [])
    }

    /// Registration before the pane, not merely alongside it: a pane opened
    /// first is a pane that does not list Ward yet.
    @Test("Registers with the system before opening the pane")
    func registersThenOpensPane() {
        #expect(
            PermissionEscalation.nextSteps(.explained(userChoseSettings: true))
                == [.registerWithSystem, .openSettingsPane]
        )
    }

    /// The invariant, over the whole stage space rather than one stage at a
    /// time. `Stage` has two cases each carrying one `Bool`, so four values is
    /// exhaustive — and if a stage is ever added, this case is what notices that
    /// the new one can hand out `.registerWithSystem` too early.
    @Test("No stage registers with the system before Ward has explained")
    func nothingRegistersBeforeExplaining() {
        let everyStage: [PermissionEscalation.Stage] = [
            .notYetAsked(isAlreadyGranted: true),
            .notYetAsked(isAlreadyGranted: false),
            .explained(userChoseSettings: true),
            .explained(userChoseSettings: false),
        ]
        for stage in everyStage {
            let steps = PermissionEscalation.nextSteps(stage)
            guard case .notYetAsked = stage else {
                continue
            }
            #expect(
                !steps.contains(.registerWithSystem),
                "\(stage) hands out the system prompt before anything has been explained"
            )
        }
    }
}
