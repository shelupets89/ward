import Testing
@testable import WardCore

/// This builds a command that runs as root and writes into /etc/sudoers.d. A
/// malformed file there breaks `sudo` machine-wide, so the shape of this command
/// is worth pinning down.
struct SudoersRuleTests {
    private let rule = SudoersRule(userName: "testuser")

    @Test("Grants the named user exactly the two lid-sleep toggles")
    func grantsOnlyTheTwoToggles() {
        #expect(rule.ruleText == "testuser ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0")
    }

    @Test("Grants no wildcard, which would let extra arguments through")
    func grantsNoWildcard() {
        #expect(!rule.ruleText.contains("*"))
        #expect(!rule.ruleText.contains("?"))
        #expect(!rule.ruleText.contains("ALL)"))
    }

    @Test("Validates with visudo before the file is installed")
    func validatesBeforeInstalling() throws {
        let command = rule.installCommand
        let validationIndex = try #require(command.range(of: "visudo -c -f"))
        let installIndex = try #require(command.range(of: "/usr/bin/install"))
        #expect(validationIndex.lowerBound < installIndex.lowerBound)
    }

    @Test("Chains every step so a failure aborts the rest")
    func chainsEveryStep() {
        let steps = rule.installCommand.components(separatedBy: " && ")
        #expect(steps.count >= 4)
        #expect(!rule.installCommand.contains(";"))
    }

    @Test("Uses absolute paths for every tool, since it runs as root")
    func usesAbsolutePaths() {
        let command = rule.installCommand
        ["/usr/bin/mktemp", "/usr/sbin/visudo", "/usr/bin/install", "/bin/rm"].forEach { toolPath in
            #expect(command.contains(toolPath))
        }
    }

    @Test("Installs read-only, root-owned, at the documented path")
    func installsWithSafePermissions() {
        #expect(rule.installCommand.contains("-m 0440 -o root -g wheel"))
        #expect(rule.installCommand.contains("/etc/sudoers.d/ward"))
        #expect(SudoersRule.installedRulePath == "/etc/sudoers.d/ward")
    }

    /// A hostile name's characters still *appear* in the command — they are data
    /// being written to a file. What matters is that they arrive inside a quoted
    /// region, so asserting the text is absent would be asserting the wrong
    /// thing. The real property is that the rule went through the quoter.
    @Test("Routes the rule through shell quoting so a hostile user name cannot break out")
    func quotesHostileUserName() {
        let hostileRule = SudoersRule(userName: "evil'; touch /tmp/pwned; '")
        let expectedQuoting = ShellQuoting.quoteForShell([hostileRule.ruleText])
        #expect(hostileRule.installCommand.contains(expectedQuoting))
        #expect(expectedQuoting.contains("'\\''"))
    }
}
