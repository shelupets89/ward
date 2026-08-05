import AppKit
import WardCore

/// Installs the narrowly-scoped sudoers rule that lets Ward toggle lid sleep
/// without a password.
///
/// This is the same rule `scripts/install-sudoers-rule.sh` writes — offered from
/// inside the app so nobody has to know a shell script exists. The rule text is
/// shown verbatim before installing: an app asking for a standing root grant
/// should say exactly what it is granting itself.
///
/// Every path is absolute because the command runs as root through `sh`, and the
/// staged file is validated with `visudo -c` before it is ever moved into
/// `/etc/sudoers.d` — an invalid file there breaks `sudo` for the whole machine.
@MainActor
enum SudoersRuleInstaller {
    private static var rule: SudoersRule {
        return SudoersRule(userName: NSUserName())
    }

    private static var rulePath: String {
        return SudoersRule.installedRulePath
    }

    static var ruleText: String {
        return rule.ruleText
    }

    /// Offers the setup and performs it. Returns whether the rule is installed
    /// afterwards — declining is not an error, it just means the password path
    /// stays in use.
    static func offerInstallation() -> Bool {
        let alert = NSAlert()
        alert.messageText = "Set up Touch ID for Keep Awake?"
        alert.informativeText = """
        Changing the lid-sleep setting needs administrator rights, so macOS asks for your password \
        every time — including when Ward tries to restore sleep on its own after the time limit runs out.

        Ward can add one rule to let it run just those two commands without a password. You will be \
        asked for your password once, now. After that, turning Keep Awake on uses Touch ID and \
        turning it off is silent.

        The exact rule:

        \(ruleText)

        Remove it any time with:  sudo rm \(rulePath)
        """
        alert.addButton(withTitle: "Set Up")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else {
            WardLogger.keepAwake.notice("Passwordless setup declined; keeping the password path.")
            return false
        }
        guard install() else {
            WardLogger.keepAwake.error("Passwordless setup failed.")
            presentFailureAlert()
            return false
        }
        WardLogger.keepAwake.info("Passwordless sudoers rule installed.")
        return true
    }

    private static func install() -> Bool {
        return PrivilegedShellRunner.run(
            executablePath: "/bin/sh",
            arguments: ["-c", rule.installCommand],
            allowInteractivePrompt: true
        )
    }

    private static func presentFailureAlert() {
        let alert = NSAlert()
        alert.messageText = "Ward couldn’t install the rule"
        alert.informativeText = """
        The authorization was declined, or the rule failed validation and was not written. Nothing \
        was changed. Keep Awake still works — it will just ask for your password each time.
        """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
