import AppKit

/// `@main` rather than top-level `main.swift` code so the entry point can be
/// main-actor isolated, matching the AppKit objects it creates.
@main
enum WardApp {
    @MainActor
    static func main() {
        let application = NSApplication.shared
        let appDelegate = AppDelegate()
        application.delegate = appDelegate
        application.setActivationPolicy(.accessory)
        application.run()
    }
}
