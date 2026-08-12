import Carbon.HIToolbox

/// Recognises the one key the exit gesture is built on.
///
/// Two overloads because the two input sources report a key code in different
/// widths — the event tap reads an `Int64` field, `NSEvent` exposes a `UInt16`
/// — and the comparison had been written inline at both call sites, in two
/// integer types, tested at neither.
public enum EscapeKeyCode {
    public static func matches(_ keyCode: Int64) -> Bool {
        return keyCode == Int64(kVK_Escape)
    }

    public static func matches(_ keyCode: UInt16) -> Bool {
        return keyCode == UInt16(kVK_Escape)
    }
}
