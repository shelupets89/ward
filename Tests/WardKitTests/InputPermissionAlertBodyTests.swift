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

private let awkwardPath = "/Users/you/My Projects/ward/dist/Ward.app"

/// The sentence both alerts share verbatim. It drifted apart once already —
/// only one alert carried it — so the tests assert it from a single source.
private let remediation = "Remove that entry with “−” and add this copy of Ward instead."

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

    /// Each sentence here is one a stub could delete while every other test
    /// still passed. The remove-and-re-add escape is the part `CLAUDE.md`
    /// records as hard-won — the stale entry keeps showing its toggle on, so
    /// "just enable it" is the one instruction that cannot work.
    @Test("Keeps every instruction the copy exists to deliver")
    func keepsEveryInstruction() {
        let accessibilityText = InputPermissionAlertBody
            .describeMissingAccessibility(runningBundlePath: localBuildPath)
        let refusedTapText = InputPermissionAlertBody
            .describeRefusedInputTap(runningBundlePath: localBuildPath)
        #expect(accessibilityText.contains("Open System Settings → Privacy & Security → Accessibility"))
        #expect(accessibilityText.contains("click Start Cleaning Mode again"))
        #expect(accessibilityText.contains("its entry keeps showing itself as enabled while granting nothing"))
        #expect(refusedTapText.contains("Enable Ward under Privacy & Security → Input Monitoring"))
        // A second action, not framing: the tap can be refused with Input
        // Monitoring on and Accessibility since switched off.
        #expect(refusedTapText.contains("(and confirm it is still enabled under Accessibility)"))
        #expect(refusedTapText.contains("quit and relaunch Ward first"))
        #expect(accessibilityText.contains("This copy of Ward is:"))
        #expect(refusedTapText.contains("This copy of Ward is:"))
        #expect(accessibilityText.contains(remediation))
        #expect(refusedTapText.contains(remediation))
    }

    /// Under `swift run` the path is a build directory, not a bundle. It is
    /// well-formed and non-blank, so the blank guard never fires, and without
    /// this the alert would invite a comparison against System Settings that
    /// cannot succeed — there is no entry for a thing that is not an app.
    ///
    /// Asserted on both alerts: Accessibility granted through the terminal and
    /// the tap still refused is precisely how the second one gets reached.
    @Test("Says so when the running build is not an app bundle at all")
    func flagsAnUnbundledBuild() {
        let accessibilityText = InputPermissionAlertBody
            .describeMissingAccessibility(runningBundlePath: unbundledBuildPath)
        let refusedTapText = InputPermissionAlertBody
            .describeRefusedInputTap(runningBundlePath: unbundledBuildPath)
        // Written out rather than looped: a loop variable would print as `text`
        // on failure, where these names say which alert broke.
        #expect(accessibilityText.contains("Ward is running from:"))
        #expect(accessibilityText.contains("\n\(unbundledBuildPath)\n"))
        #expect(accessibilityText.contains("not an app bundle"))
        #expect(accessibilityText.contains("build and launch dist/Ward.app and grant Ward itself."))
        #expect(refusedTapText.contains("Ward is running from:"))
        #expect(refusedTapText.contains("\n\(unbundledBuildPath)\n"))
        #expect(refusedTapText.contains("not an app bundle"))
        #expect(refusedTapText.contains("build and launch dist/Ward.app and grant Ward itself."))
    }

    /// The pane still matters for an unbundled build — the grant belongs to
    /// whatever launched it, and that app is listed there — but naming Ward as
    /// the thing to enable would contradict the paragraph that says the grant is
    /// not Ward's. Both alerts must point at the pane without naming Ward.
    @Test("Points an unbundled build at the pane without naming Ward as the entry")
    func pointsUnbundledBuildAtPaneWithoutNamingWard() {
        let accessibilityText = InputPermissionAlertBody
            .describeMissingAccessibility(runningBundlePath: unbundledBuildPath)
        let refusedTapText = InputPermissionAlertBody
            .describeRefusedInputTap(runningBundlePath: unbundledBuildPath)
        #expect(accessibilityText.contains("Privacy & Security → Accessibility"))
        #expect(refusedTapText.contains("Privacy & Security → Input Monitoring"))
        #expect(!accessibilityText.contains("Enable Ward"))
        #expect(!refusedTapText.contains("Enable Ward"))
    }

    /// Naming the grant's real holder is the whole value of this branch. The
    /// attribution stays hedged — a build started by launchd has no app to
    /// enable — and the rebuild is not a one-step fix either, so it says so.
    @Test("Names both fixes for an unbundled build, and overstates neither")
    func namesBothFixesForUnbundledBuild() {
        let accessibilityText = InputPermissionAlertBody
            .describeMissingAccessibility(runningBundlePath: unbundledBuildPath)
        let refusedTapText = InputPermissionAlertBody
            .describeRefusedInputTap(runningBundlePath: unbundledBuildPath)
        for text in [accessibilityText, refusedTapText] {
            #expect(text.contains("the grant belongs to whatever launched it — usually your terminal"))
            #expect(text.contains("build and launch dist/Ward.app and grant Ward itself"))
            // Xcode's attribution has never been measured here, unlike the
            // terminal's, so the copy must not name it as though it had.
            #expect(!text.contains("Xcode"))
        }
    }

    /// A stale Ward entry is not an unbundled build's problem — it was just told
    /// the grant is not Ward's — and the fix for it is withheld anyway, so the
    /// warning would dangle.
    @Test("Leaves the stale-entry warning out of an unbundled build's alert")
    func leavesStaleEntryWarningOutOfUnbundledAlert() {
        #expect(
            !InputPermissionAlertBody
                .describeMissingAccessibility(runningBundlePath: unbundledBuildPath)
                .contains("A Ward already listed there")
        )
        #expect(
            !InputPermissionAlertBody
                .describeRefusedInputTap(runningBundlePath: unbundledBuildPath)
                .contains("already listed under either pane")
        )
    }

    /// There is nothing to add, so telling the user to add it back would
    /// contradict the paragraph directly above that says nothing can match.
    @Test("Withholds the add-it-back escape when there is nothing to add")
    func withholdsRemediationForUnbundledBuild() {
        #expect(
            !InputPermissionAlertBody
                .describeMissingAccessibility(runningBundlePath: unbundledBuildPath)
                .contains(remediation)
        )
        #expect(
            !InputPermissionAlertBody
                .describeRefusedInputTap(runningBundlePath: unbundledBuildPath)
                .contains(remediation)
        )
    }

    /// `awkwardPath` earns its place here: a predicate that keyed off spaces
    /// rather than the `.app` suffix would pass against the other two.
    @Test(
        "Leaves the unbundled warning off a real bundle",
        arguments: [homebrewInstallPath, localBuildPath, awkwardPath]
    )
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

    /// Every branch, though the non-bundle one is the hazard: it nests its
    /// literal a level deeper than the rest, and Swift strips indentation
    /// relative to the closing delimiter, so a stray indent there would reach
    /// the alert as visibly ragged text that no `contains` check would notice.
    @Test(
        "Indents no rendered line, whatever the literals nest to",
        arguments: [homebrewInstallPath, unbundledBuildPath, awkwardPath, ""]
    )
    func indentsNoRenderedLine(bundlePath: String) {
        let bothTexts = [
            InputPermissionAlertBody.describeMissingAccessibility(runningBundlePath: bundlePath),
            InputPermissionAlertBody.describeRefusedInputTap(runningBundlePath: bundlePath)
        ]
        for text in bothTexts {
            #expect(text.split(separator: "\n").allSatisfy { !$0.hasPrefix(" ") })
        }
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
        // Nothing identified "this copy", so offering to add it back would
        // dangle. Holds by construction — a blank path is never `.app` — which
        // is exactly the kind of reasoning that let an earlier contradiction
        // through, so it is asserted rather than argued.
        #expect(!accessibilityText.contains(remediation))
        #expect(!refusedTapText.contains(remediation))
        // A blank path is not evidence the build is unbundled, so it takes the
        // standard body and keeps that body's instruction.
        #expect(accessibilityText.contains("Open System Settings → Privacy & Security → Accessibility"))
        #expect(refusedTapText.contains("Enable Ward under Privacy & Security → Input Monitoring"))
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
