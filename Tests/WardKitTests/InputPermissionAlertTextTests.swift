import Testing
@testable import WardKit

/// The two builds that routinely coexist on a developer's machine since the
/// Homebrew tap landed. Both are plain "Ward" in System Settings, so the alert's
/// only way to say which one is asking is the path.
private let homebrewInstallPath = "/opt/homebrew/Cellar/ward/0.2.1/Ward.app"
private let localBuildPath = "/Users/you/DoorLoop/ward/dist/Ward.app"

struct InputPermissionAlertTextTests {
    @Test(
        "Names the running build when Accessibility is missing",
        arguments: [homebrewInstallPath, localBuildPath]
    )
    func namesRunningBuildWhenAccessibilityIsMissing(bundlePath: String) {
        let text = InputPermissionAlertText.describeMissingAccessibility(runningBundlePath: bundlePath)
        #expect(text.contains("\n\(bundlePath)\n"))
    }

    @Test(
        "Names the running build when the input tap is refused",
        arguments: [homebrewInstallPath, localBuildPath]
    )
    func namesRunningBuildWhenTapIsRefused(bundlePath: String) {
        let text = InputPermissionAlertText.describeRefusedInputTap(runningBundlePath: bundlePath)
        #expect(text.contains("\n\(bundlePath)\n"))
    }

    /// The path exists to be compared, character for character, against the
    /// entry in System Settings and against `lsappinfo info -only bundlepath`.
    /// A path prettified on the way out would defeat that.
    @Test("Reproduces a path containing spaces verbatim")
    func reproducesAwkwardPathVerbatim() {
        let awkwardPath = "/Users/you/My Projects/ward/dist/Ward.app"
        let text = InputPermissionAlertText.describeMissingAccessibility(runningBundlePath: awkwardPath)
        #expect(text.contains("\n\(awkwardPath)\n"))
    }

    /// Without this, the bare path reads as decoration. The sentence explaining
    /// that a grant belongs to one build is what makes an already-listed "Ward"
    /// stop looking like proof that access was granted.
    @Test(
        "Explains that a grant belongs to one exact build",
        arguments: [homebrewInstallPath, localBuildPath]
    )
    func explainsGrantBelongsToOneBuild(bundlePath: String) {
        #expect(
            InputPermissionAlertText
                .describeMissingAccessibility(runningBundlePath: bundlePath)
                .contains("one exact build")
        )
        #expect(
            InputPermissionAlertText
                .describeRefusedInputTap(runningBundlePath: bundlePath)
                .contains("one exact build")
        )
    }

    /// Each alert opens a different Settings pane, so naming the wrong one sends
    /// the user somewhere that cannot fix anything.
    @Test("Sends each alert to its own Settings pane")
    func sendsEachAlertToItsOwnSettingsPane() {
        let accessibilityText = InputPermissionAlertText
            .describeMissingAccessibility(runningBundlePath: localBuildPath)
        let refusedTapText = InputPermissionAlertText
            .describeRefusedInputTap(runningBundlePath: localBuildPath)
        #expect(accessibilityText.contains("Accessibility"))
        #expect(!accessibilityText.contains("Input Monitoring"))
        #expect(refusedTapText.contains("Input Monitoring"))
    }

    /// `Bundle.main.bundleURL.path` never returns this, but the function is
    /// public and takes any string. A label with nothing under it would look
    /// like the alert had failed to work out what it was.
    @Test("Drops the build disclosure rather than labelling a blank path", arguments: ["", "   "])
    func dropsDisclosureForBlankPath(blankPath: String) {
        let accessibilityText = InputPermissionAlertText
            .describeMissingAccessibility(runningBundlePath: blankPath)
        let refusedTapText = InputPermissionAlertText
            .describeRefusedInputTap(runningBundlePath: blankPath)
        #expect(!accessibilityText.contains("This copy of Ward is"))
        #expect(!refusedTapText.contains("This copy of Ward is"))
        #expect(accessibilityText.contains("Accessibility"))
        #expect(refusedTapText.contains("Input Monitoring"))
    }

    /// Copy that points at the disclosure — "the build named above" — turns into
    /// a dangling reference the moment the disclosure is dropped, which is a
    /// worse dead end than saying nothing about the path at all.
    @Test("Never points at a disclosure it did not print", arguments: ["", "   "])
    func neverPointsAtAbsentDisclosure(blankPath: String) {
        #expect(
            !InputPermissionAlertText
                .describeMissingAccessibility(runningBundlePath: blankPath)
                .contains("above")
        )
        #expect(
            !InputPermissionAlertText
                .describeRefusedInputTap(runningBundlePath: blankPath)
                .contains("above")
        )
    }
}
