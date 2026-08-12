import XCTest
@testable import CleaningMode

/// Isolated to the main actor because the handlers are: the event tap and the
/// backup monitor both deliver on the main thread, and these tests exercise the
/// same routing table from the same place the app does.
@MainActor
final class InputEventHandlersTests: XCTestCase {
    private final class RoutedEventLog {
        private(set) var events: [String] = []

        func record(_ event: String) {
            events.append(event)
        }
    }

    private func makeHandlers(loggingInto log: RoutedEventLog) -> InputEventHandlers {
        return InputEventHandlers(
            onEscapeKeyDown: { log.record("escapeKeyDown") },
            onEscapeKeyUp: { log.record("escapeKeyUp") },
            onOtherKeyDown: { log.record("otherKeyDown") },
            onModifiersChanged: { areModifiersDown in
                log.record("modifiersChanged(\(areModifiersDown))")
            },
            onIrrecoverableFailure: { log.record("irrecoverableFailure") }
        )
    }

    func test_shouldStartTheHold_whenEscapeIsPressed() {
        let log = RoutedEventLog()
        let handlers = makeHandlers(loggingInto: log)
        handlers.routeKeyEvent(isEscapeKey: true, isKeyDown: true)
        XCTAssertEqual(log.events, ["escapeKeyDown"])
    }

    func test_shouldEndTheHold_whenEscapeIsReleased() {
        let log = RoutedEventLog()
        let handlers = makeHandlers(loggingInto: log)
        handlers.routeKeyEvent(isEscapeKey: true, isKeyDown: false)
        XCTAssertEqual(log.events, ["escapeKeyUp"])
    }

    func test_shouldSuppressTheHold_whenAnotherKeyIsPressed() {
        let log = RoutedEventLog()
        let handlers = makeHandlers(loggingInto: log)
        handlers.routeKeyEvent(isEscapeKey: false, isKeyDown: true)
        XCTAssertEqual(log.events, ["otherKeyDown"])
    }

    /// The one case that must stay silent: a cloth lifting off a non-escape key
    /// carries no meaning for the gesture, and firing anything here would let a
    /// key-up clear the suppression that its own key-down established.
    func test_shouldFireNothing_whenANonEscapeKeyIsReleased() {
        let log = RoutedEventLog()
        let handlers = makeHandlers(loggingInto: log)
        handlers.routeKeyEvent(isEscapeKey: false, isKeyDown: false)
        XCTAssertEqual(log.events, [])
    }

    /// Order is the gesture's correctness condition, not a detail: the tracker
    /// is a state machine, so the same three events delivered out of order leave
    /// it in a different state.
    func test_shouldPreserveDeliveryOrder_acrossAClothProofSequence() {
        let log = RoutedEventLog()
        let handlers = makeHandlers(loggingInto: log)
        handlers.routeKeyEvent(isEscapeKey: true, isKeyDown: true)
        handlers.routeKeyEvent(isEscapeKey: false, isKeyDown: true)
        handlers.routeKeyEvent(isEscapeKey: true, isKeyDown: false)
        XCTAssertEqual(log.events, ["escapeKeyDown", "otherKeyDown", "escapeKeyUp"])
    }

    func test_shouldReportModifierState_whenModifiersChange() {
        let log = RoutedEventLog()
        let handlers = makeHandlers(loggingInto: log)
        handlers.onModifiersChanged(true)
        handlers.onModifiersChanged(false)
        XCTAssertEqual(log.events, ["modifiersChanged(true)", "modifiersChanged(false)"])
    }

    func test_shouldReportFailure_whenTheTapCannotBeRecovered() {
        let log = RoutedEventLog()
        let handlers = makeHandlers(loggingInto: log)
        handlers.onIrrecoverableFailure()
        XCTAssertEqual(log.events, ["irrecoverableFailure"])
    }
}
