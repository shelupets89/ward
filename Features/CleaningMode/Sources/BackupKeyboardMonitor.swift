import AppKit
import Carbon.HIToolbox
import WardKit

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
        // The monitor block is nonisolated, but a local monitor is only ever
        // called from the app's own event dispatch — so asserting the main
        // actor here is sound, and it has to be asserted synchronously: the
        // block's return value is what consumes the event.
        monitor = NSEvent.addLocalMonitorForEvents(matching: watchedEvents) { [handlers] event in
            let monitoredEvent = MonitoredKeyEvent(event)
            MainActor.assumeIsolated {
                BackupKeyboardMonitor.route(monitoredEvent, to: handlers)
            }
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

    @MainActor
    private static func route(_ event: MonitoredKeyEvent, to handlers: InputEventHandlers) {
        switch event.type {
        case .keyDown, .keyUp:
            handlers.routeKeyEvent(isEscapeKey: event.isEscapeKey, isKeyDown: event.type == .keyDown)
        case .flagsChanged:
            handlers.onModifiersChanged(event.areModifiersDown)
        default:
            break
        }
    }
}

/// Everything the hold gesture needs from a monitored event, read off `NSEvent`
/// before the hop to the main actor — `NSEvent` is not `Sendable` and these
/// three facts are, so nothing but value types crosses the boundary.
private struct MonitoredKeyEvent: Sendable {
    let type: NSEvent.EventType
    let isEscapeKey: Bool
    let areModifiersDown: Bool

    init(_ event: NSEvent) {
        type = event.type
        isEscapeKey = event.keyCode == UInt16(kVK_Escape)
        areModifiersDown = WatchedModifiers.areDown(in: event.modifierFlags)
    }
}
