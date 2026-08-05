import IOKit.pwr_mgt

/// Holds a display-sleep assertion for as long as a feature needs one. The
/// assertion is released explicitly and dies with the process either way.
///
/// `activeAssertionID` is per-instance, so two features each holding their own
/// preventer hold two independent assertions and neither release can cancel the
/// other's. Give every feature its own instance rather than sharing one.
public final class DisplaySleepPreventer {
    private static let preventDisplaySleepAssertionType = "PreventUserIdleDisplaySleep" as CFString

    /// Shown verbatim by `pmset -g assertions`, which is where anyone asking
    /// "what is keeping this Mac awake?" looks — so it names the feature
    /// holding it, not the app.
    private let assertionName: String
    private var activeAssertionID: IOPMAssertionID?

    public init(assertionName: String) {
        self.assertionName = assertionName
    }

    public func beginPreventingDisplaySleep() -> Bool {
        guard activeAssertionID == nil else {
            return true
        }
        var createdAssertionID = IOPMAssertionID(0)
        let creationResult = IOPMAssertionCreateWithName(
            Self.preventDisplaySleepAssertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            assertionName as CFString,
            &createdAssertionID
        )
        guard creationResult == kIOReturnSuccess else {
            return false
        }
        activeAssertionID = createdAssertionID
        return true
    }

    /// Returns false if the release was refused, in which case the assertion is
    /// still held and the ID is **kept**. Forgetting it would look like success
    /// to `beginPreventingDisplaySleep`, which would then create a second
    /// assertion beside the live one — an orphan no session caps and no menu
    /// can reach, lasting until the process exits.
    @discardableResult
    public func endPreventingDisplaySleep() -> Bool {
        guard let activeAssertionID else {
            return true
        }
        let releaseResult = IOPMAssertionRelease(activeAssertionID)
        guard releaseResult == kIOReturnSuccess else {
            return false
        }
        self.activeAssertionID = nil
        return true
    }
}
