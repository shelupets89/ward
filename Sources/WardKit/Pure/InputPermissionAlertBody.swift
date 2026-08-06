/// Both alerts name the bundle that is asking. Since the Homebrew tap landed, a
/// `brew install` build and a local `make-app.sh` build routinely coexist, and
/// System Settings lists both as plain "Ward". An entry already sitting in that
/// list may belong to the other build, or to this one before a rebuild; either
/// way its switch reads as on while granting nothing, so every visible signal
/// says "granted" while the running app is refused. The path is the only thing
/// that distinguishes them, and the alert is the only place the user is looking.
///
/// Each alert is written out once per case rather than assembled from a fixed
/// frame with conditional inserts. Four reviews running, the frame kept saying
/// something the insert then contradicted — enable Ward, then the grant is not
/// Ward's — because no one reads the assembled result while editing one half of
/// it. Written whole, each message can only be wrong on its own terms.
public enum InputPermissionAlertBody {
    public static func describeMissingAccessibility(runningBundlePath: String) -> String {
        guard isRunningUnbundled(runningBundlePath) else {
            return """
            Blocking the keyboard and trackpad requires Accessibility access. Open System \
            Settings → Privacy & Security → Accessibility, then click Start Cleaning Mode again.

            \(discloseRunningBuild(runningBundlePath))macOS grants access to one exact build. A \
            Ward already listed there — another install, or this one before a rebuild — is a \
            different app to macOS, and its entry keeps showing itself as enabled while granting \
            nothing.\(remediateStaleEntry(runningBundlePath))
            """
        }
        return """
        Blocking the keyboard and trackpad requires Accessibility access, granted under System \
        Settings → Privacy & Security → Accessibility.

        \(explainUnbundledGrant(runningBundlePath))
        """
    }

    public static func describeRefusedInputTap(runningBundlePath: String) -> String {
        guard isRunningUnbundled(runningBundlePath) else {
            return """
            macOS refused the input-blocking tap. Enable Ward under Privacy & Security → Input \
            Monitoring (and confirm it is still enabled under Accessibility), then try again. If \
            you just granted access, quit and relaunch Ward first.

            \(discloseRunningBuild(runningBundlePath))macOS grants access to one exact build, so a \
            Ward already listed under either pane may be a different app whose grant does not \
            apply here.\(remediateStaleEntry(runningBundlePath))
            """
        }
        return """
        macOS refused the input-blocking tap. It needs Privacy & Security → Input Monitoring, and \
        Accessibility alongside it.

        \(explainUnbundledGrant(runningBundlePath))
        """
    }

    /// Shared by both alerts so the two cannot drift apart, which the remediation
    /// sentence already did once.
    ///
    /// "usually" is load-bearing. A build started by launchd has `ppid` 1 and no
    /// app anyone could enable, so naming the terminal outright would be wrong
    /// for it. Xcode is deliberately not named: this repo has measured the
    /// terminal's attribution and nothing else, and a guess dressed as a fact is
    /// what the alert exists to stop.
    ///
    /// Both fixes are offered because they cost differently: enabling the
    /// launcher frees the session now, while the rebuild is what makes the grant
    /// Ward's own — and it is not one step either, since a fresh ad-hoc bundle
    /// still has to be granted.
    private static func explainUnbundledGrant(_ bundlePath: String) -> String {
        return """
        Ward is running from:
        \(bundlePath)

        That is not an app bundle, so the grant belongs to whatever launched it — usually your \
        terminal — and not to Ward. Enable that in the list and run Ward again, or build and \
        launch dist/Ward.app and grant Ward itself.
        """
    }

    /// Only the standard body reaches this, so it decides between a path worth
    /// printing and nothing at all — a label with an empty line under it would
    /// read as Ward having failed to work out what it is.
    ///
    /// The blank check is deliberately narrow. It catches the degenerate string
    /// a public signature admits, not invisible Unicode: nothing feeding this
    /// can produce that, because the only caller passes
    /// `Bundle.main.bundleURL.path`. A second caller handing it arbitrary text
    /// would need more than this.
    ///
    /// The path is reproduced exactly as given. It is there to be compared
    /// character for character against the System Settings entry and against
    /// `lsappinfo info -only bundlepath`, which a tidied-up path would not match.
    private static func discloseRunningBuild(_ bundlePath: String) -> String {
        guard !bundlePath.allSatisfy(\.isWhitespace) else {
            return ""
        }
        return "This copy of Ward is:\n\(bundlePath)\n\n"
    }

    /// The one sentence both standard bodies share word for word, and only when
    /// there is something to add. A blank path never disclosed a "this copy" for
    /// it to point at. Shared rather than written out twice: it drifted once
    /// already, reaching only the Accessibility alert.
    private static func remediateStaleEntry(_ bundlePath: String) -> String {
        guard isAppBundle(bundlePath) else {
            return ""
        }
        return " Remove that entry with “−” and add this copy of Ward instead."
    }

    /// A blank path is not evidence of anything, so it takes the standard body:
    /// only a path we can see is not a bundle earns the other one.
    private static func isRunningUnbundled(_ bundlePath: String) -> Bool {
        return !bundlePath.allSatisfy(\.isWhitespace) && !isAppBundle(bundlePath)
    }

    /// `Bundle.main.bundleURL.path` resolves from the layout on disk rather than
    /// from how the process was launched, so a bundle answers `true` whether it
    /// was opened through LaunchServices or run straight off its executable —
    /// and `swift run`, which has no bundle at all, answers `false`.
    private static func isAppBundle(_ bundlePath: String) -> Bool {
        return bundlePath.hasSuffix(".app")
    }
}
