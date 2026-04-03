// CovertTimingConfigurationValidator.swift

import OpalFusion
import Testing

struct CovertTimingConfigurationValidator {
    @Test("Covert timing configuration preserves the pinned Electron Cash covert timing values")
    func validateElectronCashCovertTimingValues() {
        let covertTiming = OpalFusion.Transport.BaselineConfiguration.electronCash443.covertTiming

        #expect(covertTiming.connectTimeout == .seconds(15))
        #expect(covertTiming.connectWindow == .seconds(15))
        #expect(covertTiming.submitTimeout == .seconds(3))
        #expect(covertTiming.submitWindow == .seconds(5))
        #expect(covertTiming.spareConnectionCount == 6)
    }
}
