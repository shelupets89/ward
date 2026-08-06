/// The body copy of the two alerts that ask for an input permission.
///
/// Both name the bundle that is asking, because since the Homebrew tap a
/// `brew install` build and a local `make-app.sh` build routinely coexist and
/// System Settings lists both as plain "Ward". An entry already sitting in that
/// list may belong to the other build, or to this one before a rebuild; either
/// way its switch reads as on while granting nothing, so every visible signal
/// says "granted" while the running app is refused. The path is the only thing
/// that distinguishes them, and the alert is the only place the user is looking.
public enum InputPermissionAlertText {
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
        already listed under either pane may be a different app whose grant does not apply here.
        """
    }

    /// Returns the disclosure as its own paragraph, or nothing at all when there
    /// is no path worth printing — a label with an empty line under it would
    /// read as Ward having failed to work out what it is.
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
}
