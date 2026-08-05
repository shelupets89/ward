/// Callbacks shared by every input source (event tap, backup monitor) so both
import WardKit
/// feed the same hold-tracking logic.
struct InputEventHandlers {
    let onEscapeKeyDown: () -> Void
    let onEscapeKeyUp: () -> Void
    let onOtherKeyDown: () -> Void
    let onModifiersChanged: (_ areModifiersDown: Bool) -> Void
    let onIrrecoverableFailure: () -> Void

    /// Single routing table for both input sources: a non-escape key-up carries
    /// no meaning for the hold gesture, so it is the one case that fires nothing.
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
