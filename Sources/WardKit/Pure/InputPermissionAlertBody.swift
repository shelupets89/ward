/// Both alerts name the bundle that is asking. Since the Homebrew tap landed, a
/// `brew install` build and a local `make-app.sh` build routinely coexist, and
/// System Settings lists both as plain "Ward". An entry already sitting in that
/// list may belong to the other build, or to this one before a rebuild; either
/// way its switch reads as on while granting nothing, so every visible signal
/// says "granted" while the running app is refused. The path is the only thing
/// that distinguishes them, and the alert is the only place the user is looking.
public enum InputPermissionAlertBody {
    public static func describeMissingAccessibility(runningBundlePath: String) -> String {
        return """
        Blocking the keyboard and trackpad requires Accessibility access. Open System Settings → \
        Privacy & Security → Accessibility, then click Start Cleaning Mode again.

        \(discloseRunningBuild(runningBundlePath))macOS grants access to one exact build. A Ward \
        already listed there — another install, or this one before a rebuild — is a different app \
        to macOS, and its entry keeps showing itself as enabled while granting \
        nothing.\(remediateStaleEntry(runningBundlePath))
        """
    }

    public static func describeRefusedInputTap(runningBundlePath: String) -> String {
        return """
        macOS refused the input-blocking tap. Enable Ward under Privacy & Security → Input \
        Monitoring (and confirm it is still enabled under Accessibility), then try again. If you \
        just granted access, quit and relaunch Ward first.

        \(discloseRunningBuild(runningBundlePath))macOS grants access to one exact build, so a Ward \
        already listed under either pane may be a different app whose grant does not apply \
        here.\(remediateStaleEntry(runningBundlePath))
        """
    }

    /// Wraps whichever description applies in its own paragraph, or drops it
    /// entirely — a label with an empty line under it would read as Ward having
    /// failed to work out what it is.
    ///
    /// The blank check is deliberately narrow. It catches the degenerate string
    /// a public signature admits, not invisible Unicode: nothing feeding this
    /// can produce that, because the only caller passes
    /// `Bundle.main.bundleURL.path`. A second caller handing it arbitrary text
    /// would need more than this.
    private static func discloseRunningBuild(_ bundlePath: String) -> String {
        guard !bundlePath.allSatisfy(\.isWhitespace) else {
            return ""
        }
        return "\(describeBuildLocation(bundlePath))\n\n"
    }

    /// The path is reproduced exactly as given. It is there to be compared
    /// character for character against the System Settings entry and against
    /// `lsappinfo info -only bundlepath`, which a tidied-up path would not match.
    ///
    /// Split from the wrapping above so each has one reason to change: this one
    /// owns what the paragraph says, that one owns whether it appears at all.
    ///
    /// An unbundled build is still fixable from the same pane, which is why the
    /// instruction above is not withheld from it: macOS attributes the grant to
    /// the responsible process, so the app that launched this one is already in
    /// that list. Saying "nothing you add can match it" would be false — it is
    /// Ward that cannot be added, not the launcher. Both fixes are named because
    /// enabling the launcher fixes the session now, while the rebuild is what
    /// makes the grant belong to Ward.
    private static func describeBuildLocation(_ bundlePath: String) -> String {
        guard isAppBundle(bundlePath) else {
            return """
            Ward is running from:
            \(bundlePath)

            That is not an app bundle, so the grant belongs to whatever launched it — your \
            terminal, or Xcode — and not to Ward. Enable that app in the list instead, or build \
            and launch dist/Ward.app so the grant belongs to Ward itself.
            """
        }
        return "This copy of Ward is:\n\(bundlePath)"
    }

    /// The one sentence both alerts share word for word, and only when there is
    /// something to add. Ward itself can be added to a pane only when it is a
    /// bundle, so offering this to a build that is not one would point at
    /// something the reader cannot do. Shared rather than written out twice: it
    /// drifted once already, reaching only the Accessibility alert.
    private static func remediateStaleEntry(_ bundlePath: String) -> String {
        guard isAppBundle(bundlePath) else {
            return ""
        }
        return " Remove that entry with “−” and add this copy of Ward instead."
    }

    /// `Bundle.main.bundleURL.path` resolves from the layout on disk rather than
    /// from how the process was launched, so a bundle answers `true` whether it
    /// was opened through LaunchServices or run straight off its executable —
    /// and `swift run`, which has no bundle at all, answers `false`.
    private static func isAppBundle(_ bundlePath: String) -> Bool {
        return bundlePath.hasSuffix(".app")
    }
}
