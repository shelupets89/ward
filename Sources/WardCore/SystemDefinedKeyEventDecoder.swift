/// Decodes the `data1` payload of an aux-control-button system event — the
/// form media, volume, and brightness keys arrive in.
public enum SystemDefinedKeyEventDecoder {
    /// Bits 8–15 of `data1` hold the key state; the rest carry the key code and
    /// flags, which is why the field is masked rather than compared whole.
    private static let keyStateShift = 8
    private static let keyStateMask = 0xFF
    private static let pressedKeyState = 0x0A

    public static func isAuxiliaryButtonPress(data1: Int) -> Bool {
        let keyState = (data1 >> keyStateShift) & keyStateMask
        return keyState == pressedKeyState
    }
}
