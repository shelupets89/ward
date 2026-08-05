import AppKit

/// Modifiers that make an esc press non-deliberate (a cloth wiping the bottom
/// row presses these). Caps Lock is excluded: its flag reports toggle state,
/// not a held key, and would permanently block the exit gesture.
public enum WatchedModifiers {
    public static let cgEventFlags: CGEventFlags = [
        .maskCommand, .maskAlternate, .maskControl, .maskShift, .maskSecondaryFn
    ]
    public static let nsEventFlags: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift, .function
    ]

    public static func areDown(in eventFlags: CGEventFlags) -> Bool {
        return !eventFlags.intersection(cgEventFlags).isEmpty
    }

    public static func areDown(in modifierFlags: NSEvent.ModifierFlags) -> Bool {
        return !modifierFlags.intersection(nsEventFlags).isEmpty
    }
}
