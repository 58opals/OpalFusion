// RoundTimingConfigurationValidator.swift

import OpalFusion
import Testing

struct RoundTimingConfigurationValidator {
    @Test("Round timing configuration preserves the pinned Electron Cash round timing values")
    func validateElectronCashRoundTimingValues() {
        let roundTiming = OpalFusion.Transport.BaselineConfiguration.electronCash443.roundTiming

        #expect(roundTiming.maximumClockDiscrepancy == .seconds(5))
        #expect(roundTiming.warmupDuration == .seconds(30))
        #expect(roundTiming.warmupSlop == .seconds(3))
        #expect(roundTiming.commitmentsDeadlineFromRoundStart == .seconds(3))
        #expect(roundTiming.covertComponentsStartFromRoundStart == .seconds(5))
        #expect(roundTiming.covertComponentsDeadlineFromRoundStart == .seconds(15))
        #expect(roundTiming.signaturesStartFromRoundStart == .seconds(20))
        #expect(roundTiming.signaturesDeadlineFromRoundStart == .seconds(30))
        #expect(roundTiming.conclusionTimeoutFromRoundStart == .seconds(35))
        #expect(roundTiming.closeStartFromRoundStart == .seconds(45))
        #expect(roundTiming.blameCloseStartFromRoundStart == .seconds(80))
        #expect(roundTiming.standardTimeout == .seconds(3))
        #expect(roundTiming.blameVerifyDuration == .seconds(5))
    }
}
