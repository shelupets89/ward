import Testing
@testable import WardCore

struct SystemDefinedKeyEventDecoderTests {
    @Test("should report press when the state nibble is the press value")
    func detectsPress() {
        let pressData1 = 0x0A << 8
        #expect(SystemDefinedKeyEventDecoder.isAuxiliaryButtonPress(data1: pressData1))
    }

    @Test("should report not-press when the state nibble is the release value")
    func detectsRelease() {
        let releaseData1 = 0x0B << 8
        #expect(!SystemDefinedKeyEventDecoder.isAuxiliaryButtonPress(data1: releaseData1))
    }

    @Test("should ignore bits outside the state nibble")
    func ignoresKeyCodeAndFlagBits() {
        let pressWithKeyCodeAndFlags = (3 << 16) | (0x0A << 8) | 0x1
        #expect(SystemDefinedKeyEventDecoder.isAuxiliaryButtonPress(data1: pressWithKeyCodeAndFlags))
    }

    @Test("should report not-press when the state nibble is zero")
    func reportsNotPressForZero() {
        #expect(!SystemDefinedKeyEventDecoder.isAuxiliaryButtonPress(data1: 0))
    }
}
