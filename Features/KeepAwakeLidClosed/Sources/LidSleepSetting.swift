import Foundation
import WardKit

/// Whether this Mac may sleep when the lid closes.
///
/// `unknown` is deliberately distinct from `enabled`: failing to *read* the flag
/// is not evidence that sleep works. Collapsing the two would make the leak
/// check silently skip the one condition it exists to catch.
enum LidSleepState {
    case enabled
    case disabled
    case unknown

    var mayBeDisabled: Bool {
        switch self {
        case .disabled, .unknown:
            return true
        case .enabled:
            return false
        }
    }
}

/// The `pmset disablesleep` flag — the only lever macOS offers for staying
/// awake with the lid shut. Power assertions deliberately do not cover clamshell
/// sleep, which is a demand sleep rather than an idle one.
///
/// This flag is persistent global system state: it survives app quit, crash, and
/// reboot. Everything that sets it is responsible for clearing it.
enum LidSleepSetting {
    private static let pmsetExecutablePath = "/usr/bin/pmset"
    private static let sudoExecutablePath = "/usr/bin/sudo"
    private static let disableArguments = ["-a", "disablesleep", "1"]
    private static let enableArguments = ["-a", "disablesleep", "0"]

    static var currentState: LidSleepState {
        let outcome = BoundedProcess.run(
            executablePath: pmsetExecutablePath,
            arguments: ["-g"],
            capturesOutput: true
        )
        guard outcome.didSucceed else {
            return .unknown
        }
        return SleepSettingsParser.isSleepDisabled(in: outcome.standardOutput) ? .disabled : .enabled
    }

    /// Whether the sudoers rule is installed, checked with `sudo -n -l`, which
    /// resolves permission without running the command or prompting.
    ///
    /// This decides whether a Touch ID gate is worth showing: if the toggle will
    /// raise a password dialog anyway, a second prompt is friction, not safety.
    static var isPasswordlessToggleAvailable: Bool {
        return BoundedProcess.run(
            executablePath: sudoExecutablePath,
            arguments: ["-n", "-l", pmsetExecutablePath] + disableArguments
        ).didSucceed
    }

    static func disableSleep(allowInteractivePrompt: Bool) -> Bool {
        return PrivilegedShellRunner.run(
            executablePath: pmsetExecutablePath,
            arguments: disableArguments,
            allowInteractivePrompt: allowInteractivePrompt
        )
    }

    static func enableSleep(allowInteractivePrompt: Bool) -> Bool {
        return PrivilegedShellRunner.run(
            executablePath: pmsetExecutablePath,
            arguments: enableArguments,
            allowInteractivePrompt: allowInteractivePrompt
        )
    }
}
