// CovertPayloadProtocolValidator.swift

import OpalFusion
import Testing

struct CovertPayloadProtocolValidator {
    @Test("Covert payload models preserve raw bytes and optional fields")
    func validateCovertPayloadProtocolModels() {
        let covertComponent = OpalFusion.ProtocolModel.CovertComponent(
            roundPublicKey: [0x01, 0x02],
            signature: [0x03, 0x04],
            serializedComponent: [0x05, 0x06]
        )
        let sharedComponents = OpalFusion.ProtocolModel.ShareCovertComponents(
            serializedComponents: [
                [0x10, 0x11],
                [0x12, 0x13]
            ],
            skipSignatures: true,
            sessionHash: [0x20, 0x21]
        )
        let covertTransactionSignature = OpalFusion.ProtocolModel.CovertTransactionSignature(
            inputIndex: 7,
            transactionSignature: [0x30, 0x31]
        )

        #expect(covertComponent.roundPublicKey == [0x01, 0x02])
        #expect(covertComponent.signature == [0x03, 0x04])
        #expect(covertComponent.serializedComponent == [0x05, 0x06])
        #expect(sharedComponents.serializedComponents == [[0x10, 0x11], [0x12, 0x13]])
        #expect(sharedComponents.skipSignatures == true)
        #expect(sharedComponents.sessionHash == [0x20, 0x21])
        #expect(covertTransactionSignature.roundPublicKey == nil)
        #expect(covertTransactionSignature.inputIndex == 7)
        #expect(covertTransactionSignature.transactionSignature == [0x30, 0x31])
    }
}
