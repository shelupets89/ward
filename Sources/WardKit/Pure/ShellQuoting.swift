/// Quoting for the two layers a privileged command passes through: a shell
/// command line, and an AppleScript string literal wrapping it.
///
/// Everything quoted here is a compile-time literal today. It is written to be
/// safe for arbitrary input anyway — quoting that only works for today's call
/// sites is a trap for whoever adds a dynamic value later.
public enum ShellQuoting {
    /// POSIX single-quoting: wrap in `'…'` and close-escape-reopen around any
    /// embedded quote (`'\''`). Inside single quotes the shell expands nothing,
    /// so `$(…)`, backticks, `;` and `&&` are all inert.
    public static func quoteForShell(_ commandParts: [String]) -> String {
        return commandParts
            .map { part in
                let escaped = part.replacingOccurrences(of: "'", with: "'\\''")
                return "'\(escaped)'"
            }
            .joined(separator: " ")
    }

    /// Backslashes must be escaped before quotes: doing it the other way round
    /// would re-escape the backslashes this step just inserted.
    public static func quoteForAppleScript(_ value: String) -> String {
        let escaped = value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }
}
