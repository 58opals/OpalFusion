// FrameConfigurationValidator.swift

import OpalFusion
import Testing

struct FrameConfigurationValidator {
    @Test("Frame configuration preserves the pinned Electron Cash framing values")
    func validateElectronCashFramingValues() {
        let frameConfiguration = OpalFusion.Transport.BaselineConfiguration.electronCash443.framing

        #expect(
            frameConfiguration.magicBytes == [0x76, 0x5b, 0xe8, 0xb4, 0xe4, 0x39, 0x6d, 0xcf]
        )
        #expect(frameConfiguration.maximumMessageLengthBytes == 200 * 1024)
    }
}
