import Testing
@testable import WardCore

struct SleepSettingsParserTests {
    private let realPmsetOutput = """
    System-wide power settings:
     SleepDisabled\t\t1
     DestroyFVKeyOnStandby\t\t1
    Currently in use:
     standbydelaylow      10800
     standby              1
     womp                 1
     halfdim              1
     hibernatefile        /var/vm/sleepimage
     powernap             1
     lowpowermode         0
     ttyskeepawake        1
     displaysleep         10
     tcpkeepalive         1
     disksleep            10
    """

    @Test("Reports disabled when the flag is set in real pmset output")
    func reportsDisabledFromRealOutput() {
        #expect(SleepSettingsParser.isSleepDisabled(in: realPmsetOutput))
    }

    @Test("Reports enabled when the flag is absent entirely")
    func reportsEnabledWhenFlagAbsent() {
        let outputWithoutFlag = """
        System-wide power settings:
         DestroyFVKeyOnStandby\t\t1
        Currently in use:
         displaysleep         10
        """
        #expect(!SleepSettingsParser.isSleepDisabled(in: outputWithoutFlag))
    }

    @Test("Reports enabled when the flag is explicitly zero")
    func reportsEnabledWhenFlagIsZero() {
        #expect(!SleepSettingsParser.isSleepDisabled(in: " SleepDisabled\t\t0"))
    }

    @Test("Tolerates spaces instead of tabs")
    func toleratesSpaceSeparator() {
        #expect(SleepSettingsParser.isSleepDisabled(in: "  SleepDisabled   1  "))
    }

    @Test("Ignores a value that merely contains the key name")
    func ignoresSubstringMatches() {
        #expect(!SleepSettingsParser.isSleepDisabled(in: " NotSleepDisabledReally\t\t1"))
    }

    @Test("Reports enabled for empty output rather than guessing")
    func reportsEnabledForEmptyOutput() {
        #expect(!SleepSettingsParser.isSleepDisabled(in: ""))
    }
}
