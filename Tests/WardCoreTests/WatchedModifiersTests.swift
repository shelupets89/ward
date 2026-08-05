import Testing
import AppKit
@testable import WardCore

struct WatchedModifiersTests {
    @Test("should report false when no CG modifiers are down")
    func reportsFalseForEmptyCGFlags() {
        #expect(!WatchedModifiers.areDown(in: CGEventFlags()))
    }

    @Test(
        "should report true when a watched CG modifier is down",
        arguments: [
            CGEventFlags.maskCommand,
            .maskAlternate,
            .maskControl,
            .maskShift,
            .maskSecondaryFn
        ]
    )
    func reportsTrueForEachWatchedCGModifier(flag: CGEventFlags) {
        #expect(WatchedModifiers.areDown(in: flag))
    }

    @Test("should report false when only the Caps Lock CG flag is set")
    func ignoresCapsLockCGFlag() {
        #expect(!WatchedModifiers.areDown(in: .maskAlphaShift))
    }

    @Test("should report true when Caps Lock and Command are both set")
    func detectsCommandAlongsideCapsLockCGFlag() {
        #expect(WatchedModifiers.areDown(in: [.maskAlphaShift, .maskCommand]))
    }

    @Test("should report false when no NS modifiers are down")
    func reportsFalseForEmptyNSFlags() {
        #expect(!WatchedModifiers.areDown(in: NSEvent.ModifierFlags()))
    }

    @Test(
        "should report true when a watched NS modifier is down",
        arguments: [
            NSEvent.ModifierFlags.command,
            .option,
            .control,
            .shift,
            .function
        ]
    )
    func reportsTrueForEachWatchedNSModifier(flag: NSEvent.ModifierFlags) {
        #expect(WatchedModifiers.areDown(in: flag))
    }

    @Test("should report false when only the Caps Lock NS flag is set")
    func ignoresCapsLockNSFlag() {
        #expect(!WatchedModifiers.areDown(in: .capsLock))
    }
}
