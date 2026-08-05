import Foundation
import WardCore

/// Runs a fixed root-only command.
///
/// Two paths, tried in order: a passwordless sudo rule scoped to exactly these
/// commands (see `scripts/install-sudoers-rule.sh`), then macOS's own
/// authorization dialog. The dialog collects the password itself — Ward
/// never sees, stores, or types it.
///
/// The non-interactive path matters for more than convenience: the safety
/// restore on quit has to be able to run without a modal dialog blocking it.
enum PrivilegedShellRunner {
    private static let sudoExecutablePath = "/usr/bin/sudo"

    static func run(
        executablePath: String,
        arguments: [String],
        allowInteractivePrompt: Bool
    ) -> Bool {
        if runWithPasswordlessSudo(executablePath: executablePath, arguments: arguments) {
            return true
        }
        guard allowInteractivePrompt else {
            return false
        }
        return runWithAuthorizationPrompt(executablePath: executablePath, arguments: arguments)
    }

    private static func runWithPasswordlessSudo(executablePath: String, arguments: [String]) -> Bool {
        return BoundedProcess.run(
            executablePath: sudoExecutablePath,
            arguments: ["-n", executablePath] + arguments
        ).didSucceed
    }

    private static func runWithAuthorizationPrompt(executablePath: String, arguments: [String]) -> Bool {
        let shellCommand = ShellQuoting.quoteForShell([executablePath] + arguments)
        let source = "do shell script \(ShellQuoting.quoteForAppleScript(shellCommand)) with administrator privileges"
        guard let appleScript = NSAppleScript(source: source) else {
            WardLogger.keepAwake.error("Could not compile the authorization script.")
            return false
        }
        var scriptError: NSDictionary?
        appleScript.executeAndReturnError(&scriptError)
        guard let scriptError else {
            return true
        }
        WardLogger.keepAwake.notice("Authorization declined or failed: \(scriptError, privacy: .public)")
        return false
    }
}
