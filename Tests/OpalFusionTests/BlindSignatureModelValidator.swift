// BlindSignatureModelValidator.swift

import OpalFusion
import Testing

struct BlindSignatureModelValidator {
    @Test("Blind signature models preserve scalar bytes and array usage")
    func validateBlindSignatureModels() {
        let request = OpalFusion.BlindSignature.Request(
            scalar: [0x01, 0x02, 0x03]
        )
        let response = OpalFusion.BlindSignature.Response(
            scalar: [0xAA, 0xBB, 0xCC]
        )
        let responses = OpalFusion.ProtocolModel.BlindSignatureResponses(
            responses: [response]
        )

        #expect(Self.requireSendable(request) == request)
        #expect(Self.requireSendable(response) == response)
        #expect(request.scalar == [0x01, 0x02, 0x03])
        #expect(response.scalar == [0xAA, 0xBB, 0xCC])
        #expect(responses.responses == [response])
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
