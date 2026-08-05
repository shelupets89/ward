import Testing
@testable import FreePort

/// The port a user types is the only free-text input to a destructive action,
/// so anything the parser is unsure about must be rejected rather than guessed.
struct PortSpecParserTests {
    @Test(
        "Parses the forms a developer actually types",
        arguments: ["3001", ":3001", "tcp:3001", "TCP:3001", " 3001 ", "\t:3001\n", " tcp:3001 "]
    )
    func parsesAcceptedForms(spec: String) {
        #expect(PortSpecParser.parse(spec) == 3001)
    }

    @Test("Accepts the lowest and highest usable ports")
    func acceptsBoundaries() {
        #expect(PortSpecParser.parse("1") == 1)
        #expect(PortSpecParser.parse("65535") == 65535)
    }

    @Test(
        "Rejects anything outside the usable range",
        arguments: ["0", "65536", "-1", "99999", "4294967296"]
    )
    func rejectsOutOfRange(spec: String) {
        #expect(PortSpecParser.parse(spec) == nil)
    }

    @Test(
        "Rejects input that is not a bare port",
        arguments: ["abc", "", "   ", ":", "tcp:", "3001abc", "30 01", "3001:3002", "udp:3001", "+3001", "3_001"]
    )
    func rejectsNonPorts(spec: String) {
        #expect(PortSpecParser.parse(spec) == nil)
    }

    /// Unicode calls these digits; `kill` does not. Confusable numerals are the
    /// one class of input worth naming for the only free-text route into an
    /// irreversible action.
    @Test(
        "Rejects non-ASCII numerals",
        arguments: ["\u{FF13}\u{FF10}\u{FF10}\u{FF11}", "\u{0663}\u{0660}\u{0660}\u{0661}", "\u{00B2}"]
    )
    func rejectsNonASCIINumerals(spec: String) {
        #expect(PortSpecParser.parse(spec) == nil)
    }
}
