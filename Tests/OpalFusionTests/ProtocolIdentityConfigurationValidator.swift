// ProtocolIdentityConfigurationValidator.swift

import OpalFusion
import Testing

struct ProtocolIdentityConfigurationValidator {
    @Test("Protocol identity configuration preserves the pinned Electron Cash identity values")
    func validateElectronCashProtocolIdentityValues() {
        let protocolIdentity = OpalFusion.Transport.BaselineConfiguration.electronCash443.protocolIdentity

        #expect(Self.requireSendable(protocolIdentity) == protocolIdentity)
        #expect(protocolIdentity.versionBytes == [0x61, 0x6C, 0x70, 0x68, 0x61, 0x31, 0x33])
        #expect(protocolIdentity.fusionLokadId == [0x46, 0x55, 0x5A, 0x00])
        #expect(protocolIdentity.minimumOutputAmountSatoshis == 10_000)
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
