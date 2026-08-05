import os

/// Cleaning mode blocks all input, so a failure can't be reported through the
/// UI it just hid — every failure and recovery path logs here instead, readable
/// afterwards in Console.app.
public enum WardLogger {
    public static let cleaningMode = Logger(subsystem: "com.dimashelupets.ward", category: "cleaning-mode")
    public static let inputBlocking = Logger(subsystem: "com.dimashelupets.ward", category: "input-blocking")
    public static let keepAwake = Logger(subsystem: "com.dimashelupets.ward", category: "keep-awake")
}
