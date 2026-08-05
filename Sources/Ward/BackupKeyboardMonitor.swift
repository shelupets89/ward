import AppKit
import Carbon.HIToolbox
import WardCore

/// Second exit path: if the event tap ever goes silent while the shield is the
/// key window, keyboard events still reach the app and this monitor routes them
/// into the same hold-tracking handlers (and consumes them locally).
final class BackupKeyboardMonitor {
    private let handlers: InputEventHandlers
    private var monitor: Any?

    init(handlers: InputEventHandlers) {
        self.handlers = handlers
    }

    func start() -> Bool {
        guard monitor == nil else {
            return true
        }
        let watchedEvents: NSEvent.EventTypeMask = [.keyDown, .keyUp, .flagsChanged]
        monitor = NSEvent.addLocalMonitorForEvents(matching: watchedEvents) { [handlers] event in
            BackupKeyboardMonitor.route(event, to: handlers)
            return nil
        }
        return monitor != nil
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }

    private static func route(_ event: NSEvent, to handlers: InputEventHandlers) {
        switch event.type {
        case .keyDown, .keyUp:
            handlers.routeKeyEvent(
                isEscapeKey: event.keyCode == UInt16(kVK_Escape),
                isKeyDown: event.type == .keyDown
            )
        case .flagsChanged:
            handlers.onModifiersChanged(WatchedModifiers.areDown(in: event.modifierFlags))
        default:
            break
        }
    }
}
