import IOKit.pwr_mgt

/// Keeps the display awake while cleaning mode is active so the exit
/// instructions stay visible. The assertion is released on exit and dies with
/// the process either way.
public final class DisplaySleepPreventer {
    private static let preventDisplaySleepAssertionType = "PreventUserIdleDisplaySleep" as CFString

    private var activeAssertionID: IOPMAssertionID?

    public init() {}

    public func beginPreventingDisplaySleep() -> Bool {
        guard activeAssertionID == nil else {
            return true
        }
        var createdAssertionID = IOPMAssertionID(0)
        let creationResult = IOPMAssertionCreateWithName(
            Self.preventDisplaySleepAssertionType,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            "Ward cleaning session" as CFString,
            &createdAssertionID
        )
        guard creationResult == kIOReturnSuccess else {
            return false
        }
        activeAssertionID = createdAssertionID
        return true
    }

    public func endPreventingDisplaySleep() {
        guard let activeAssertionID else {
            return
        }
        IOPMAssertionRelease(activeAssertionID)
        self.activeAssertionID = nil
    }
}
