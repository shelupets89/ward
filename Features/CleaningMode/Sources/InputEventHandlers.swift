/// Callbacks shared by every input source (event tap, backup monitor) so both
import WardKit
/// feed the same hold-tracking logic.
/// Every handler runs on the main actor because every one of them ends in
/// `CleaningModeController` state. Declaring that here is what lets the struct
/// be `Sendable` — the tap hands it across a `DispatchQueue.main.async` — while
/// the closures themselves stay fully checked.
struct InputEventHandlers: Sendable {
    let onEscapeKeyDown: @MainActor @Sendable () -> Void
    let onEscapeKeyUp: @MainActor @Sendable () -> Void
    let onOtherKeyDown: @MainActor @Sendable () -> Void
    let onModifiersChanged: @MainActor @Sendable (_ areModifiersDown: Bool) -> Void
    let onIrrecoverableFailure: @MainActor @Sendable () -> Void

    /// Single routing table for both input sources: a non-escape key-up carries
    /// no meaning for the hold gesture, so it is the one case that fires nothing.
    @MainActor
    func routeKeyEvent(isEscapeKey: Bool, isKeyDown: Bool) {
        switch (isEscapeKey, isKeyDown) {
        case (true, true):
            onEscapeKeyDown()
        case (true, false):
            onEscapeKeyUp()
        case (false, true):
            onOtherKeyDown()
        case (false, false):
            break
        }
    }
}
