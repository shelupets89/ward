/// The narrowly-scoped sudoers rule that lets Ward toggle lid sleep without a
/// password, plus the command that installs it.
///
/// Two properties matter more than anything else here, and both are tested:
/// the rule contains **no wildcards** (so `sudoers` matches the arguments
/// literally and no extra argument can be smuggled in), and the staged file is
/// **validated by `visudo` before it reaches `/etc/sudoers.d`** — an invalid file
/// there breaks `sudo` for the entire machine.
///
/// The user name is injected rather than read from the process so this stays
/// pure and testable.
public struct SudoersRule {
    public static let installedRulePath = "/etc/sudoers.d/ward"

    private static let comment =
        "# Installed by Ward. Allows toggling lid-close sleep without a password prompt. Nothing else."

    public let userName: String

    public init(userName: String) {
        self.userName = userName
    }

    public var ruleText: String {
        return "\(userName) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 1, /usr/bin/pmset -a disablesleep 0"
    }

    /// A single `&&`-chained line: any step failing aborts the rest and reports a
    /// non-zero status, so a rule that fails validation never reaches disk.
    /// Absolute paths throughout because this runs as root under `sh`.
    public var installCommand: String {
        let stagedFile = "\"$staged\""
        return [
            "staged=$(/usr/bin/mktemp)",
            "printf '%s\\n' \(quoted(Self.comment)) \(quoted(ruleText)) > \(stagedFile)",
            "/usr/sbin/visudo -c -f \(stagedFile) > /dev/null",
            "/usr/bin/install -m 0440 -o root -g wheel \(stagedFile) \(quoted(Self.installedRulePath))",
            "/bin/rm -f \(stagedFile)"
        ].joined(separator: " && ")
    }

    private func quoted(_ value: String) -> String {
        return ShellQuoting.quoteForShell([value])
    }
}
