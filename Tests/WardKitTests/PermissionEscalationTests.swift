import Testing
@testable import WardKit

/// The ordering these cases hold is the one that shipped: the system prompt
/// fired before Ward's alert, so two modals arrived together and the one that
/// could name the bundle was behind the one that could not.
///
/// Every case asserts an exact array. Membership would pass against every wrong
/// order, since each of them contains the right steps — which is how an ordering
/// test stops testing the ordering. An earlier version of this file kept a
/// `contains` case alongside these and claimed in the same breath to use none;
/// it was removed rather than the sentence softened, because it caught nothing
/// the exact-array cases did not already catch.
struct PermissionEscalationTests {
    @Test("Asks for nothing when the permission is already granted")
    func silentWhenAlreadyGranted() {
        #expect(PermissionEscalation.nextSteps(.notYetAsked(isAlreadyGranted: true)) == [])
    }

    /// The regression case. Handing out `.registerWithSystem` here is exactly
    /// what the old code did.
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

    /// Which pane each button opens was glue until it was data, and glue got it
    /// wrong silently: swapping the two URL constants pointed a button reading
    /// "Open Accessibility Settings" at the Input Monitoring pane, and the whole
    /// suite stayed green.
    @Test("Sends each grant to its own pane")
    func eachGrantNamesItsOwnPane() {
        #expect(PermissionEscalation.Grant.accessibility.settingsURLString.hasSuffix("Privacy_Accessibility"))
        #expect(PermissionEscalation.Grant.inputMonitoring.settingsURLString.hasSuffix("Privacy_ListenEvent"))
    }

    @Test("Labels each grant's button with the pane it opens")
    func eachGrantNamesItsOwnButton() {
        #expect(PermissionEscalation.Grant.accessibility.settingsButtonTitle == "Open Accessibility Settings")
        #expect(PermissionEscalation.Grant.inputMonitoring.settingsButtonTitle == "Open Input Monitoring Settings")
    }

    /// Exhaustive for real, over `allCases` rather than a hand-typed list a new
    /// case would never join. Two grants sharing a pane, or a title, is the
    /// copy-paste this notices — including for a third grant nobody has thought
    /// of yet.
    @Test("No two grants share a pane or a button title")
    func grantsAreDistinct() {
        let panes = PermissionEscalation.Grant.allCases.map(\.settingsURLString)
        let titles = PermissionEscalation.Grant.allCases.map(\.settingsButtonTitle)
        #expect(Set(panes).count == PermissionEscalation.Grant.allCases.count)
        #expect(Set(titles).count == PermissionEscalation.Grant.allCases.count)
    }
}
