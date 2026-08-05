import os

/// Cleaning mode blocks all input, so a failure can't be reported through the
/// UI it just hid — every failure and recovery path logs here instead, readable
/// afterwards in Console.app.
public enum WardLogger {
    public static let cleaningMode = Logger(subsystem: "com.dimashelupets.ward", category: "cleaning-mode")
    public static let inputBlocking = Logger(subsystem: "com.dimashelupets.ward", category: "input-blocking")
    /// Lid-closed keep-awake and screen keep-awake get separate categories
    /// despite the shared name. They have opposite failure models, so filtering
    /// `keep-awake` must not mix a failed sleep-setting restore — which needs
    /// the user to act — with a session that merely ended.
    public static let keepAwake = Logger(subsystem: "com.dimashelupets.ward", category: "keep-awake")
    public static let keepScreenAwake = Logger(subsystem: "com.dimashelupets.ward", category: "keep-screen-awake")
    public static let freePort = Logger(subsystem: "com.dimashelupets.ward", category: "free-port")
}
