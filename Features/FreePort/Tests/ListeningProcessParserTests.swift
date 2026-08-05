import Testing
@testable import FreePort

/// Fixtures are real `lsof -iTCP -sTCP:LISTEN -P -n` output from a development
/// Mac, including the ControlCenter rows that make the confirmation dialog
/// necessary and the IPv4/IPv6 pairs that make deduplication necessary.
struct ListeningProcessParserTests {
    private let realLsofOutput = """
    COMMAND     PID          USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
    rapportd   1276 dimashelupets   10u  IPv4 0x2906e852ceb595b5      0t0  TCP *:55401 (LISTEN)
    rapportd   1276 dimashelupets   13u  IPv6 0xd380d511572cba91      0t0  TCP *:55401 (LISTEN)
    ControlCe  1327 dimashelupets    9u  IPv4 0xe0d71c179aacbada      0t0  TCP *:7000 (LISTEN)
    ControlCe  1327 dimashelupets   10u  IPv6  0x1c424d85b860ea0      0t0  TCP *:7000 (LISTEN)
    ControlCe  1327 dimashelupets   11u  IPv4 0xea19763bdb85cf1e      0t0  TCP *:5000 (LISTEN)
    ControlCe  1327 dimashelupets   12u  IPv6 0xeb0bfde50ce47fd3      0t0  TCP *:5000 (LISTEN)
    node      26036 dimashelupets   67u  IPv6 0x2c01dd8f5febcf86      0t0  TCP *:3001 (LISTEN)
    node      28281 dimashelupets   21u  IPv6 0xd33d97ee2af0f1f9      0t0  TCP [::1]:9229 (LISTEN)
    node      28281 dimashelupets   22u  IPv4 0xe46d72069213828b      0t0  TCP 127.0.0.1:9229 (LISTEN)
    Code\\x20H 84580 dimashelupets  192u  IPv6 0x6e029dbf215ca503      0t0  TCP *:9735 (LISTEN)
    """

    private func parsedRealOutput() -> [ListeningProcess] {
        return ListeningProcessParser.parse(realLsofOutput)
    }

    @Test("Skips the header row rather than reading it as a process")
    func skipsHeaderRow() {
        #expect(parsedRealOutput().allSatisfy { $0.command != "COMMAND" })
    }

    @Test("Reads command, pid, user and port from a wildcard IPv4 row")
    func readsWildcardRow() {
        let onPort3001 = parsedRealOutput().filter { $0.port == 3001 }
        #expect(onPort3001 == [
            ListeningProcess(command: "node", processIdentifier: 26036, user: "dimashelupets", port: 3001)
        ])
    }

    @Test("Reads the port from a bracketed IPv6 address")
    func readsBracketedIPv6Address() {
        #expect(parsedRealOutput().contains { $0.processIdentifier == 28281 && $0.port == 9229 })
    }

    @Test("Collapses the IPv4 and IPv6 rows of one process into a single entry")
    func collapsesAddressFamilyDuplicates() {
        let onPort9229 = parsedRealOutput().filter { $0.port == 9229 }
        #expect(onPort9229.count == 1)
        #expect(onPort9229.first?.processIdentifier == 28281)
    }

    @Test("Keeps one entry per port when a single process holds several")
    func keepsOneEntryPerPortOfTheSameProcess() {
        let controlCenterPorts = parsedRealOutput()
            .filter { $0.processIdentifier == 1327 }
            .map(\.port)
            .sorted()
        #expect(controlCenterPorts == [5000, 7000])
    }

    @Test("Decodes the hex escapes lsof uses for spaces in command names")
    func decodesEscapedCommandName() {
        let editor = parsedRealOutput().first { $0.processIdentifier == 84580 }
        #expect(editor?.command == "Code H")
    }

    @Test("Leaves an escape it cannot decode exactly as lsof printed it")
    func leavesUndecodableEscapesAlone() {
        let unknownEscapeRow = """
        Code\\xZZH 84580 dimashelupets  192u  IPv6 0x6e02      0t0  TCP *:9735 (LISTEN)
        """
        #expect(ListeningProcessParser.parse(unknownEscapeRow).first?.command == "Code\\xZZH")
    }

    @Test("Names a process by command and pid, never by a bare count")
    func describesProcessForConfirmation() {
        let server = ListeningProcess(command: "node", processIdentifier: 26036, user: "dimashelupets", port: 3001)
        #expect(server.displayName == "node (pid 26036)")
    }

    @Test("Returns nothing for the empty output lsof gives when no port matches")
    func returnsNothingForEmptyOutput() {
        #expect(ListeningProcessParser.parse("").isEmpty)
    }

    @Test(
        "Skips malformed rows instead of throwing",
        arguments: [
            "node      26036 dimashelupets   67u  IPv6",
            "node      notapid dimashelupets   67u  IPv6 0x2c0      0t0  TCP *:3001 (LISTEN)",
            "node      26036 dimashelupets   67u  IPv6 0x2c0      0t0  TCP *:notaport (LISTEN)",
            "node      26036 dimashelupets   67u  IPv6 0x2c0      0t0  TCP *:70000 (LISTEN)",
            "lsof: WARNING: can't stat() hfs file system /private/var/folders/zz",
            "      Output information may be incomplete."
        ]
    )
    func skipsMalformedRows(malformedLine: String) {
        #expect(ListeningProcessParser.parse(malformedLine).isEmpty)
    }

    @Test("Keeps the good rows when a malformed row sits between them")
    func keepsGoodRowsAroundAMalformedOne() {
        let mixedOutput = """
        COMMAND     PID          USER   FD   TYPE             DEVICE SIZE/OFF NODE NAME
        lsof: WARNING: can't stat() hfs file system /private/var/folders/zz
        node      26036 dimashelupets   67u  IPv6 0x2c01dd8f5febcf86      0t0  TCP *:3001 (LISTEN)
        """
        #expect(ListeningProcessParser.parse(mixedOutput).map(\.port) == [3001])
    }

    @Test("Skips a row whose pid is not positive, which kill would read as a broadcast")
    func skipsNonPositiveProcessIdentifiers() {
        let broadcastRow = """
        node          0 dimashelupets   67u  IPv6 0x2c0      0t0  TCP *:3001 (LISTEN)
        node         -1 dimashelupets   67u  IPv6 0x2c0      0t0  TCP *:3002 (LISTEN)
        """
        #expect(ListeningProcessParser.parse(broadcastRow).isEmpty)
    }

    @Test("Skips a row that is not in the LISTEN state")
    func skipsNonListeningRows() {
        let establishedRow = "node      26036 dimashelupets   67u  IPv6 0x2c0      0t0  TCP *:3001 (ESTABLISHED)"
        #expect(ListeningProcessParser.parse(establishedRow).isEmpty)
    }

    @Test("Skips a row with no state column at all, not just one with the wrong state")
    func skipsRowMissingTheStateColumn() {
        let rowWithoutState = "node      26036 dimashelupets   67u  IPv6 0x2c0      0t0  TCP *:3001"
        #expect(ListeningProcessParser.parse(rowWithoutState).isEmpty)
    }
}
