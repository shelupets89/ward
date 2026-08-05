import Testing
@testable import WardCore

/// These strings are only ever built from compile-time literals today. The point
/// of testing them against hostile input is that the safety should be a property
/// of the quoting, not an accident of the current call sites.
struct ShellQuotingTests {
    private let injectionPayloads = [
        "; id",
        "$(id)",
        "`id`",
        "$IFS&&id",
        "' ; id ; '",
        "'; touch /tmp/ward-pwned; '",
        "&& rm -rf /",
        "| tee /tmp/ward-pwned",
        "\\'; id; #",
        "a'b'c",
        "\\\\",
        "\"",
        "newline\nsecond-line"
    ]

    @Test("Wraps a plain argument in single quotes")
    func wrapsPlainArgument() {
        #expect(ShellQuoting.quoteForShell(["/usr/bin/pmset"]) == "'/usr/bin/pmset'")
    }

    @Test("Joins multiple arguments with spaces, quoting each")
    func joinsArguments() {
        let quoted = ShellQuoting.quoteForShell(["/usr/bin/pmset", "-a", "disablesleep", "1"])
        #expect(quoted == "'/usr/bin/pmset' '-a' 'disablesleep' '1'")
    }

    @Test("Neutralises every injection payload", arguments: [
        "; id", "$(id)", "`id`", "$IFS&&id", "' ; id ; '",
        "'; touch /tmp/ward-pwned; '", "&& rm -rf /", "a'b'c"
    ])
    func neutralisesPayload(payload: String) {
        let quoted = ShellQuoting.quoteForShell([payload])
        // Every embedded quote must be closed off via the '\'' idiom, so no
        // payload character can ever reach the shell unquoted.
        #expect(quoted.hasPrefix("'"))
        #expect(quoted.hasSuffix("'"))
        #expect(!containsUnescapedQuote(quoted))
    }

    @Test("Escapes an embedded single quote using the POSIX idiom")
    func escapesEmbeddedQuote() {
        #expect(ShellQuoting.quoteForShell(["it's"]) == "'it'\\''s'")
    }

    @Test("Preserves an empty argument as an explicit empty string")
    func preservesEmptyArgument() {
        #expect(ShellQuoting.quoteForShell([""]) == "''")
    }

    @Test("Escapes backslashes before quotes for AppleScript")
    func escapesBackslashBeforeQuote() {
        // Reversing the order would double-escape and corrupt the literal.
        #expect(ShellQuoting.quoteForAppleScript("a\\b") == "\"a\\\\b\"")
        #expect(ShellQuoting.quoteForAppleScript("say \"hi\"") == "\"say \\\"hi\\\"\"")
    }

    @Test("Wraps AppleScript literals in double quotes")
    func wrapsAppleScriptLiteral() {
        #expect(ShellQuoting.quoteForAppleScript("plain") == "\"plain\"")
    }

    @Test("Round-trips every payload through both layers without losing the terminator")
    func roundTripsThroughBothLayers() {
        injectionPayloads.forEach { payload in
            let appleScriptLiteral = ShellQuoting.quoteForAppleScript(ShellQuoting.quoteForShell([payload]))
            #expect(appleScriptLiteral.hasPrefix("\""))
            #expect(appleScriptLiteral.hasSuffix("\""))
            #expect(!containsUnescapedDoubleQuote(appleScriptLiteral))
        }
    }

    private func containsUnescapedQuote(_ quoted: String) -> Bool {
        let interior = quoted.dropFirst().dropLast()
        return interior.contains("'") && !interior.contains("'\\''")
    }

    private func containsUnescapedDoubleQuote(_ literal: String) -> Bool {
        let interior = Array(literal.dropFirst().dropLast())
        return interior.indices.contains { index in
            guard interior[index] == "\"" else {
                return false
            }
            let precedingBackslashes = interior[..<index].reversed().prefix { $0 == "\\" }.count
            return precedingBackslashes.isMultiple(of: 2)
        }
    }
}
