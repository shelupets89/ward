import Foundation

/// Runs a child process with a deadline.
///
/// Every caller here runs on the main actor, so an unbounded `waitUntilExit()`
/// would freeze the whole app — including the menu and the expiry timer — if
/// `pmset` or `sudo` ever hung. Bounded beats infinite.
///
/// stdin is `/dev/null` on purpose: `sudo` must fail fast rather than block
/// forever trying to read a password nobody can type.
public enum BoundedProcess {
    private static let timeout: TimeInterval = 10

    public struct Outcome {
        public let didSucceed: Bool
        public let standardOutput: String
    }

    public static func run(
        executablePath: String,
        arguments: [String],
        capturesOutput: Bool = false
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
            WardLogger.keepAwake.error("Could not launch \(executablePath, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return Outcome(didSucceed: false, standardOutput: "")
        }
        guard didFinish.wait(timeout: .now() + timeout) == .success else {
            WardLogger.keepAwake.error("\(executablePath, privacy: .public) exceeded its deadline; terminating.")
            process.terminate()
            return Outcome(didSucceed: false, standardOutput: "")
        }
        // Read only after exit: the pipe is at EOF, so this cannot block. A child
        // that outran the pipe buffer would have hit the deadline above instead.
        let outputData = outputPipe?.fileHandleForReading.readDataToEndOfFile() ?? Data()
        return Outcome(
            didSucceed: process.terminationStatus == 0,
            standardOutput: String(data: outputData, encoding: .utf8) ?? ""
        )
    }
}
