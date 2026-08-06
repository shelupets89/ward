/// Both alerts name the bundle that is asking, because since the Homebrew tap a
/// `brew install` build and a local `make-app.sh` build routinely coexist and
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
        to macOS, and its entry keeps showing itself as enabled while granting nothing. Remove that \
        entry with “−” and add this copy of Ward instead.
        """
    }

    public static func describeRefusedInputTap(runningBundlePath: String) -> String {
        return """
        macOS refused the input-blocking tap. Enable Ward under Privacy & Security → Input \
        Monitoring (and confirm it is still enabled under Accessibility), then try again. If you \
        just granted access, quit and relaunch Ward first.

        \(discloseRunningBuild(runningBundlePath))macOS grants access to one exact build, so a Ward \
        already listed under either pane may be a different app whose grant does not apply here. \
        Remove that entry with “−” and add this copy of Ward instead.
        """
    }

    /// The paragraph separator lives here and nowhere else, so neither branch of
    /// `describeBuildLocation` has to end in invisible blank lines to line up.
    ///
    /// Nothing at all when there is no path worth printing — a label with an
    /// empty line under it would read as Ward having failed to work out what it
    /// is. The blank check is deliberately narrow: the only caller passes
    /// `Bundle.main.bundleURL.path`, so it guards the degenerate string a public
    /// signature admits, not invisible Unicode that a real path cannot contain.
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
    /// A path with no `.app` on the end is what `Bundle.main.bundleURL.path`
    /// reports under `swift run` — the directory holding the executable. It is
    /// non-blank and well-formed, so it arrives here looking like any other
    /// path, and printing it plainly would invite a comparison against System
    /// Settings that cannot succeed: there is no entry for a thing that is not
    /// an app.
    private static func describeBuildLocation(_ bundlePath: String) -> String {
        guard bundlePath.hasSuffix(".app") else {
            return """
            Ward is running from:
            \(bundlePath)

            That is not an app bundle, so nothing you add in System Settings can match it — a \
            build started this way is granted through whatever launched it, usually your \
            terminal. Build and launch dist/Ward.app instead.
            """
        }
        return "This copy of Ward is:\n\(bundlePath)"
    }
}
