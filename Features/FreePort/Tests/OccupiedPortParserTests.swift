import Testing
@testable import FreePort

/// Fixtures are real `netstat -an -p tcp` output. This parser exists because an
/// unprivileged `lsof` cannot see other users' sockets at all: without the
/// cross-check, a root-held port reads as "nothing was listening", which is the
/// one answer the user must never be given about a port that is in use.
struct OccupiedPortParserTests {
    private let realNetstatOutput = """
    Active Internet connections (including servers)
    Proto Recv-Q Send-Q  Local Address          Foreign Address        (state)
    tcp4       0      0  10.6.12.2.59142        89.194.204.110.27017   SYN_SENT
    tcp46      0      0  *.3001                 *.*                    LISTEN
    tcp4       0      0  *.3000                 *.*                    LISTEN
    tcp6       0      0  ::1.9229               *.*                    LISTEN
    tcp6       0      0  *.7000                 *.*                    LISTEN
    tcp4       0      0  127.0.0.1.61062        *.*                    LISTEN
    tcp4       0      0  10.6.12.2.55123        140.82.121.6.443       ESTABLISHED
    """

    private func parsedRealOutput() -> Set<UInt16> {
        return OccupiedPortParser.listeningPorts(in: realNetstatOutput)
    }

    @Test("Reads a wildcard IPv4 listener")
    func readsWildcardIPv4Listener() {
        #expect(parsedRealOutput().contains(3000))
    }

    @Test("Reads a listener bound to a specific loopback address")
    func readsLoopbackListener() {
        #expect(parsedRealOutput().contains(61062))
    }

    @Test("Reads an IPv6 listener whose address itself contains colons")
    func readsIPv6Listener() {
        #expect(parsedRealOutput().contains(9229))
    }

    @Test("Reads a dual-stack tcp46 listener")
    func readsDualStackListener() {
        #expect(parsedRealOutput().contains(3001))
    }

    @Test("Ignores connections that are not listening")
    func ignoresNonListeningRows() {
        #expect(!parsedRealOutput().contains(27017))
        #expect(!parsedRealOutput().contains(443))
        #expect(!parsedRealOutput().contains(59142))
        #expect(!parsedRealOutput().contains(55123))
    }

    @Test("Ignores the banner and header rows")
    func ignoresHeaderRows() {
        #expect(parsedRealOutput() == [3000, 3001, 7000, 9229, 61062])
    }

    @Test("Reports a port as occupied only when something is listening on it")
    func reportsOccupancyPerPort() {
        #expect(OccupiedPortParser.isPortOccupied(3000, in: realNetstatOutput))
        #expect(!OccupiedPortParser.isPortOccupied(3002, in: realNetstatOutput))
    }

    @Test("Returns nothing for empty output rather than throwing")
    func returnsNothingForEmptyOutput() {
        #expect(OccupiedPortParser.listeningPorts(in: "").isEmpty)
    }

    @Test(
        "Skips malformed rows instead of throwing",
        arguments: [
            "tcp4       0      0  LISTEN",
            "tcp4       0      0  *.notaport             *.*                    LISTEN",
            "tcp4       0      0  *.70000                *.*                    LISTEN",
            "tcp4       0      0  noport                 *.*                    LISTEN"
        ]
    )
    func skipsMalformedRows(malformedLine: String) {
        #expect(OccupiedPortParser.listeningPorts(in: malformedLine).isEmpty)
    }
}
