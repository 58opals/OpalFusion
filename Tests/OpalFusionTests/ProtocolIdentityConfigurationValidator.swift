// ProtocolIdentityConfigurationValidator.swift

@testable import OpalFusion
import Foundation
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

    @Test("Protocol primitives preserve the official CashFusion Pedersen base tag")
    func validateOfficialPedersenBaseTag() {
        var expectedBasePoint: [UInt8] = [0x02]
        expectedBasePoint.append(contentsOf: "CashFusion gives us fungibility.".utf8)

        #expect(Array(OpalFusion.Execution.ProtocolPrimitives.pedersenAlternateBasePoint) == expectedBasePoint)
    }

    @Test("Protocol primitives place FUSE_ID before the session hash in OP_RETURN")
    func validateFuseIdentifierScriptPush() {
        let script = OpalFusion.Execution.ProtocolPrimitives.makeSessionHashLockingScript(
            sessionHash: [0xAA, 0xBB],
            baseline: .electronCash443
        )

        #expect(script == [0x6A, 0x04, 0x46, 0x55, 0x5A, 0x00, 0x02, 0xAA, 0xBB])
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
