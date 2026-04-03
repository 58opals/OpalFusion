// TransportBaselineConfigurationValidator.swift

import OpalFusion
import Testing

struct TransportBaselineConfigurationValidator {
    @Test("Transport baseline configuration exposes the pinned Electron Cash 4.4.3 profile")
    func validateElectronCashBaseline() {
        let baseline = OpalFusion.Transport.BaselineConfiguration.electronCash443

        #expect(Self.requireSendable(baseline) == baseline)
        #expect(baseline.framing.magicBytes == [0x76, 0x5b, 0xe8, 0xb4, 0xe4, 0x39, 0x6d, 0xcf])
        #expect(baseline.framing.maximumMessageLengthBytes == 200 * 1024)
        #expect(baseline.covertTiming.spareConnectionCount == 6)
        #expect(baseline.roundTiming.warmupDuration == .seconds(30))
        #expect(baseline.roundTiming.conclusionTimeoutFromRoundStart == .seconds(35))
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
