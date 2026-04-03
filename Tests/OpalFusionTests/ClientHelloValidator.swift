// ClientHelloValidator.swift

import OpalFusion
import Testing

struct ClientHelloValidator {
    @Test("Client hello is constructible with required version bytes and optional genesis hash")
    func validateClientHelloConstruction() {
        let hello = OpalFusion.ProtocolModel.ClientHello(
            versionBytes: [0x61, 0x6C, 0x70, 0x68, 0x61, 0x31, 0x33],
            genesisHash: [0xAA, 0xBB, 0xCC]
        )

        let sendableHello = Self.requireSendable(hello)

        #expect(sendableHello == hello)
        #expect(hello.versionBytes == [0x61, 0x6C, 0x70, 0x68, 0x61, 0x31, 0x33])
        #expect(hello.genesisHash == [0xAA, 0xBB, 0xCC])
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
