import AppKit
import SwiftUI

/// Covers every screen with a black borderless window above all other UI.
final class ShieldWindowsController {
    private let overlayModel: ShieldOverlayModel
    private var shieldWindows: [NSWindow] = []

    init(overlayModel: ShieldOverlayModel) {
        self.overlayModel = overlayModel
    }

    /// Fails when macOS reports no screens (it can, mid-reconfiguration): input
    /// would still be blocked with nothing on screen explaining how to get out.
    func showShields() -> Bool {
        let screens = NSScreen.screens
        guard !screens.isEmpty else {
            return false
        }
        shieldWindows = screens.map { screen in
            return makeShieldWindow(for: screen)
        }
        shieldWindows.forEach { window in
            window.makeKeyAndOrderFront(nil)
        }
        return true
    }

    /// New shields go up before the old ones come down, so a display change
    /// never leaves the desktop briefly exposed.
    func rebuildShields() -> Bool {
        let previousWindows = shieldWindows
        shieldWindows = []
        let didShowShields = showShields()
        guard didShowShields else {
            shieldWindows = previousWindows
            return false
        }
        close(previousWindows)
        return true
    }

    func closeShields() {
        close(shieldWindows)
        shieldWindows = []
    }

    private func makeShieldWindow(for screen: NSScreen) -> NSWindow {
        let window = KeyableShieldWindow(
            contentRect: screen.frame,
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        window.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        window.backgroundColor = .black
        window.isOpaque = true
        window.hasShadow = false
        window.isReleasedWhenClosed = false
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = NSHostingView(rootView: ShieldView(overlayModel: overlayModel))
        return window
    }

    private func close(_ windows: [NSWindow]) {
        windows.forEach { window in
            window.orderOut(nil)
            window.close()
        }
    }
}

/// Borderless windows refuse key status by default; the shield must be the key
/// window so the backup keyboard monitor receives events.
private final class KeyableShieldWindow: NSWindow {
    override var canBecomeKey: Bool {
        return true
    }

    override var canBecomeMain: Bool {
        return true
    }
}
