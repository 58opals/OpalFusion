// TransportBaselineConfigurationValidator.swift

import OpalFusion
import Testing

struct TransportBaselineConfigurationValidator {
    @Test("Transport baseline configuration exposes the pinned Electron Cash 4.4.3 profile")
    func validateElectronCashBaseline() {
        let baseline = OpalFusion.Transport.BaselineConfiguration.electronCash443

        #expect(Self.requireSendable(baseline) == baseline)
        #expect(baseline.protocolIdentity.versionBytes == [0x61, 0x6C, 0x70, 0x68, 0x61, 0x31, 0x33])
        #expect(baseline.protocolIdentity.fusionLokadId == [0x46, 0x55, 0x5A, 0x00])
        #expect(baseline.protocolIdentity.minimumOutputAmountSatoshis == 10_000)
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
