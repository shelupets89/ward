/// Reads the lid-sleep flag out of `pmset -g` output.
import WardKit
///
/// The parser matches the key as a whole field rather than a substring, so a
/// future setting whose name merely contains "SleepDisabled" cannot be
/// mistaken for the flag itself. Anything it cannot positively read as "1"
/// counts as sleep-enabled — the safe reading, since it means the app will try
/// to restore a setting that is already safe rather than leave a live one set.
public enum SleepSettingsParser {
    private static let sleepDisabledKey = "SleepDisabled"
    private static let disabledValue = "1"

    public static func isSleepDisabled(in pmsetOutput: String) -> Bool {
        let flagValues = pmsetOutput
            .split(separator: "\n")
            .compactMap { line -> String? in
                let fields = line.split(whereSeparator: \.isWhitespace)
                guard fields.count >= 2, String(fields[0]) == sleepDisabledKey else {
                    return nil
                }
                return String(fields[1])
            }
        return flagValues.first == disabledValue
    }
}
