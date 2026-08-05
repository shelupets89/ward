import AppKit
import Carbon.HIToolbox
import WardCore

/// Session-wide active event tap that swallows every HID event while running.
/// Esc, other-key, and modifier activity is forwarded to the handlers before
/// being swallowed; everything else is silently consumed.
final class InputBlocker {
    /// The legacy "system-defined" CGEventType and the aux-control-button
    /// NSEvent subtype have no named constants in the public API; media,
    /// volume, and brightness keys arrive as this pair.
    private static let systemDefinedEventTypeValue: UInt32 = 14
    private static let auxiliaryControlButtonSubtype: Int16 = 8

    private let handlers: InputEventHandlers
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    init(handlers: InputEventHandlers) {
        self.handlers = handlers
    }

    func start() -> Bool {
        guard eventTap == nil else {
            return true
        }
        let allEventsMask: CGEventMask = ~0
        let selfPointer = Unmanaged.passUnretained(self).toOpaque()
        let createdTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: allEventsMask,
            callback: inputBlockerTapCallback,
            userInfo: selfPointer
        )
        guard let createdTap else {
            WardLogger.inputBlocking.error("CGEvent.tapCreate returned nil — permission missing or denied.")
            return false
        }
        // Without a run loop source the tap exists but never fires, which would
        // shield the screen while every keystroke still reached the app beneath.
        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, createdTap, 0) else {
            WardLogger.inputBlocking.error("Failed to create run loop source for event tap.")
            CFMachPortInvalidate(createdTap)
            return false
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: createdTap, enable: true)
        eventTap = createdTap
        runLoopSource = source
        return true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }

    fileprivate func handleTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            recoverDisabledTap()
        case .keyDown, .keyUp:
            routeKeyboardEvent(type: type, event: event)
        case .flagsChanged:
            routeModifiersEvent(event)
        default:
            routeSystemDefinedEventIfNeeded(type: type, event: event)
        }
        return nil
    }

    private func routeKeyboardEvent(type: CGEventType, event: CGEvent) {
        let isEscapeKey = event.getIntegerValueField(.keyboardEventKeycode) == Int64(kVK_Escape)
        let isKeyDown = type == .keyDown
        deliverToHandlers { handlers in
            handlers.routeKeyEvent(isEscapeKey: isEscapeKey, isKeyDown: isKeyDown)
        }
    }

    private func routeModifiersEvent(_ event: CGEvent) {
        let areModifiersDown = WatchedModifiers.areDown(in: event.flags)
        deliverToHandlers { handlers in
            handlers.onModifiersChanged(areModifiersDown)
        }
    }

    private func routeSystemDefinedEventIfNeeded(type: CGEventType, event: CGEvent) {
        guard type.rawValue == Self.systemDefinedEventTypeValue else {
            return
        }
        guard let systemEvent = NSEvent(cgEvent: event),
              systemEvent.subtype.rawValue == Self.auxiliaryControlButtonSubtype else {
            return
        }
        guard SystemDefinedKeyEventDecoder.isAuxiliaryButtonPress(data1: systemEvent.data1) else {
            return
        }
        deliverToHandlers { handlers in
            handlers.onOtherKeyDown()
        }
    }

    private func recoverDisabledTap() {
        guard let eventTap else {
            return
        }
        WardLogger.inputBlocking.warning("Event tap disabled by the system; re-enabling.")
        CGEvent.tapEnable(tap: eventTap, enable: true)
        if CGEvent.tapIsEnabled(tap: eventTap) {
            WardLogger.inputBlocking.info("Event tap re-enabled successfully.")
        } else {
            WardLogger.inputBlocking.error("Event tap could not be re-enabled; exiting cleaning mode.")
            deliverToHandlers { handlers in
                handlers.onIrrecoverableFailure()
            }
        }
    }

    /// The tap callback runs on the main run loop, but handlers can tear this
    /// tap down (`onIrrecoverableFailure` → `stop()` invalidates the very mach
    /// port mid-dispatch), so delivery is deferred to a later run loop turn
    /// rather than unwinding through the callback that triggered it.
    private func deliverToHandlers(_ deliver: @escaping (InputEventHandlers) -> Void) {
        DispatchQueue.main.async { [handlers] in
            deliver(handlers)
        }
    }
}

private func inputBlockerTapCallback(
    proxy: CGEventTapProxy,
    type: CGEventType,
    event: CGEvent,
    userInfo: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let userInfo else {
        // Unreachable in practice, but swallowing matches the tap's contract:
        // never let an event through while cleaning mode looks active.
        return nil
    }
    let inputBlocker = Unmanaged<InputBlocker>.fromOpaque(userInfo).takeUnretainedValue()
    return inputBlocker.handleTapEvent(type: type, event: event)
}
