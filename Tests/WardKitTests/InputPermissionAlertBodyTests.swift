import Testing
@testable import WardKit

/// The two builds that routinely coexist on a developer's machine since the
/// Homebrew tap landed. Both are plain "Ward" in System Settings, so the alert's
/// only way to say which one is asking is the path.
private let homebrewInstallPath = "/opt/homebrew/Cellar/ward/0.2.1/Ward.app"
private let localBuildPath = "/Users/you/DoorLoop/ward/dist/Ward.app"

/// What `Bundle.main.bundleURL.path` reports under `swift run`: the directory
/// holding the executable, with no `.app` anywhere in it.
private let unbundledBuildPath = "/Users/you/DoorLoop/ward/.build/arm64-apple-macosx/debug"

struct InputPermissionAlertBodyTests {
    @Test(
        "Names the running build when Accessibility is missing",
        arguments: [homebrewInstallPath, localBuildPath]
    )
    func namesRunningBuildWhenAccessibilityIsMissing(bundlePath: String) {
        let text = InputPermissionAlertBody.describeMissingAccessibility(runningBundlePath: bundlePath)
        #expect(text.contains("\n\(bundlePath)\n"))
    }

    @Test(
        "Names the running build when the input tap is refused",
        arguments: [homebrewInstallPath, localBuildPath]
    )
    func namesRunningBuildWhenTapIsRefused(bundlePath: String) {
        let text = InputPermissionAlertBody.describeRefusedInputTap(runningBundlePath: bundlePath)
        #expect(text.contains("\n\(bundlePath)\n"))
    }

    /// Also the only case where the path contains whitespace without consisting
    /// of it, which is the boundary the blank guard turns on.
    @Test("Reproduces a path containing spaces verbatim")
    func reproducesAwkwardPathVerbatim() {
        let awkwardPath = "/Users/you/My Projects/ward/dist/Ward.app"
        let text = InputPermissionAlertBody.describeMissingAccessibility(runningBundlePath: awkwardPath)
        #expect(text.contains("\n\(awkwardPath)\n"))
    }

    /// Without this sentence the bare path reads as decoration, so it is worth
    /// pinning even though harmless rewording will break the assertion.
    @Test(
        "Explains that a grant belongs to one exact build",
        arguments: [homebrewInstallPath, localBuildPath]
    )
    func explainsGrantBelongsToOneBuild(bundlePath: String) {
        #expect(
            InputPermissionAlertBody
                .describeMissingAccessibility(runningBundlePath: bundlePath)
                .contains("one exact build")
        )
        #expect(
            InputPermissionAlertBody
                .describeRefusedInputTap(runningBundlePath: bundlePath)
                .contains("one exact build")
        )
    }

    @Test("Sends each alert to its own Settings pane")
    func sendsEachAlertToItsOwnSettingsPane() {
        let accessibilityText = InputPermissionAlertBody
            .describeMissingAccessibility(runningBundlePath: localBuildPath)
        let refusedTapText = InputPermissionAlertBody
            .describeRefusedInputTap(runningBundlePath: localBuildPath)
        #expect(accessibilityText.contains("Accessibility"))
        #expect(!accessibilityText.contains("Input Monitoring"))
        #expect(refusedTapText.contains("Input Monitoring"))
    }

    /// The remediation is the whole reason the user is reading this. It is also
    /// the part `CLAUDE.md` records as hard-won — the stale entry keeps showing
    /// its toggle on, so "just enable it" is the one instruction that cannot work.
    @Test("Keeps the remediation that the copy exists to deliver", arguments: [homebrewInstallPath, localBuildPath])
    func keepsRemediation(bundlePath: String) {
        let accessibilityText = InputPermissionAlertBody
            .describeMissingAccessibility(runningBundlePath: bundlePath)
        let refusedTapText = InputPermissionAlertBody
            .describeRefusedInputTap(runningBundlePath: bundlePath)
        #expect(accessibilityText.contains("click Start Cleaning Mode again"))
        #expect(refusedTapText.contains("quit and relaunch Ward first"))
        // Both panes key a grant to one build, so both need the remove-and-re-add
        // escape. Asserted on both so the pair cannot drift apart.
        #expect(accessibilityText.contains("Remove that entry with “−”"))
        #expect(refusedTapText.contains("Remove that entry with “−”"))
    }

    /// Under `swift run` the path is a build directory, not a bundle. It is
    /// well-formed and non-blank, so the blank guard never fires, and without
    /// this the alert would invite a comparison against System Settings that
    /// cannot succeed — there is no entry for a thing that is not an app.
    @Test("Says so when the running build is not an app bundle at all")
    func flagsAnUnbundledBuild() {
        let text = InputPermissionAlertBody.describeMissingAccessibility(runningBundlePath: unbundledBuildPath)
        #expect(text.contains("\n\(unbundledBuildPath)\n"))
        #expect(text.contains("not an app bundle"))
        #expect(text.contains("dist/Ward.app"))
    }

    @Test("Leaves the unbundled warning off a real bundle", arguments: [homebrewInstallPath, localBuildPath])
    func leavesUnbundledWarningOffABundle(bundlePath: String) {
        #expect(
            !InputPermissionAlertBody
                .describeMissingAccessibility(runningBundlePath: bundlePath)
                .contains("not an app bundle")
        )
        #expect(
            !InputPermissionAlertBody
                .describeRefusedInputTap(runningBundlePath: bundlePath)
                .contains("not an app bundle")
        )
    }

    /// `Bundle.main.bundleURL.path` never returns this, but the function is
    /// public and takes any string. A label with nothing under it would look
    /// like the alert had failed to work out what it was.
    @Test("Drops the build disclosure rather than labelling a blank path", arguments: ["", "   "])
    func dropsDisclosureForBlankPath(blankPath: String) {
        let accessibilityText = InputPermissionAlertBody
            .describeMissingAccessibility(runningBundlePath: blankPath)
        let refusedTapText = InputPermissionAlertBody
            .describeRefusedInputTap(runningBundlePath: blankPath)
        #expect(!accessibilityText.contains("This copy of Ward is"))
        #expect(!refusedTapText.contains("This copy of Ward is"))
        #expect(accessibilityText.contains("Accessibility"))
        #expect(refusedTapText.contains("Input Monitoring"))
    }

    /// A tripwire for one specific word, not proof against the whole class. The
    /// first draft ended "add the build named above", which dangles as soon as
    /// the disclosure is dropped; a paraphrase would still get past this.
    @Test("Never points at a disclosure it did not print", arguments: ["", "   "])
    func neverPointsAtAbsentDisclosure(blankPath: String) {
        #expect(
            !InputPermissionAlertBody
                .describeMissingAccessibility(runningBundlePath: blankPath)
                .contains("above")
        )
        #expect(
            !InputPermissionAlertBody
                .describeRefusedInputTap(runningBundlePath: blankPath)
                .contains("above")
        )
    }
}
