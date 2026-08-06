import Foundation
import os

/// Runs a child process with a deadline.
///
/// An unbounded `waitUntilExit()` blocks whichever thread called it until the
/// child decides to exit. On the main actor — where the keep-awake callers run —
/// that freezes the whole app, menu and expiry timer included, if `pmset` or
/// `sudo` ever hangs. FreePort deliberately calls from off the main actor, and
/// still needs the deadline: a stuck `lsof` would otherwise pin a thread and
/// leave the user's request unanswered forever. Bounded beats infinite either way.
///
/// stdin is `/dev/null` on purpose: `sudo` must fail fast rather than block
/// forever trying to read a password nobody can type.
public enum BoundedProcess {
    private static let timeout: TimeInterval = 10

    public struct Outcome {
        /// The process launched and exited before the deadline. Distinct from
        /// `didSucceed`: a tool like `lsof` exits non-zero to say "nothing
        /// matched", so a caller that cannot tell that apart from "never ran"
        /// will read a failed check as an empty result.
        public let didRun: Bool
        public let didSucceed: Bool
        public let standardOutput: String
    }

    /// - Parameter logger: the calling feature's category. Shared infrastructure
    ///   logging under one feature's name files "lsof never launched" under
    ///   `keep-awake`, where whoever is debugging FreePort will not look.
    public static func run(
        executablePath: String,
        arguments: [String],
        capturesOutput: Bool = false,
        logger: Logger = WardLogger.keepAwake
    ) -> Outcome {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let outputPipe = capturesOutput ? Pipe() : nil
        process.standardOutput = outputPipe ?? FileHandle.nullDevice

        let didFinish = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in
            didFinish.signal()
        }
        do {
            try process.run()
        } catch {
            logger.error("Could not launch \(executablePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return Outcome(didRun: false, didSucceed: false, standardOutput: "")
        }
        guard didFinish.wait(timeout: .now() + timeout) == .success else {
            logger.error("\(executablePath, privacy: .public) exceeded its deadline; terminating.")
            process.terminate()
            return Outcome(didRun: false, didSucceed: false, standardOutput: "")
        }
        // Read only after exit: the pipe is at EOF, so this cannot block. A child
        // that outran the pipe buffer would have hit the deadline above instead.
        let outputData = outputPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        return Outcome(
            didRun: true,
            didSucceed: process.terminationStatus == 0,
            standardOutput: String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}
