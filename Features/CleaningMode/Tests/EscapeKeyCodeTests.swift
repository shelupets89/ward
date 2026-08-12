import Testing
import Carbon.HIToolbox
@testable import CleaningMode

struct EscapeKeyCodeTests {
    @Test("should recognise escape from the tap's Int64 key code field")
    func recognisesEscapeFromCGKeyCode() {
        #expect(EscapeKeyCode.matches(Int64(kVK_Escape)))
    }

    @Test("should recognise escape from an NSEvent's UInt16 key code")
    func recognisesEscapeFromNSKeyCode() {
        #expect(EscapeKeyCode.matches(UInt16(kVK_Escape)))
    }

    /// The keys a cloth presses alongside esc. Each must read as "not escape",
    /// or a stray press would extend a hold instead of suppressing it.
    @Test(
        "should reject the keys surrounding escape on the keyboard",
        arguments: [kVK_ANSI_Grave, kVK_Tab, kVK_F1, kVK_ANSI_1, kVK_ANSI_Q]
    )
    func rejectsNeighbouringKeys(keyCode: Int) {
        #expect(!EscapeKeyCode.matches(Int64(keyCode)))
        #expect(!EscapeKeyCode.matches(UInt16(keyCode)))
    }

    /// The tap's field is signed and the monitor's is not, so the two overloads
    /// disagree about what values even exist. Neither may report a match for
    /// anything but esc.
    @Test("should reject values outside the key code range")
    func rejectsOutOfRangeValues() {
        #expect(!EscapeKeyCode.matches(Int64(-1)))
        #expect(!EscapeKeyCode.matches(Int64.max))
        #expect(!EscapeKeyCode.matches(UInt16.max))
    }
}
