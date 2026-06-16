// CashFusionOfficialProtobufFixtureValidator+BlameCovertPayloads.swift

@testable import OpalFusion
import Testing

extension CashFusionOfficialProtobufFixtureValidator {
    @Test("CashFusion blame payload codecs match official manual bytes")
    func validateBlamePayloadOfficialBytes() throws {
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.MyProofsList(
                encryptedProofs: [],
                randomNumber: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.myProofsListRequiredEmptyRandomNumberBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeMyProofsList
        )
        try expectPrimaryPayload(
            OpalFusion.Blame.RelayedProof(
                encryptedProof: [],
                sourceCommitmentIndex: 0,
                destinationKeyIndex: 0
            ),
            bytes: CashFusionOfficialProtobufFixtures.relayedProofRequiredZeroBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeRelayedProof
        )
        try expectPrimaryPayload(
            OpalFusion.Blame.BlameProof(
                proofIndex: 0,
                decrypter: .sessionKey(secretBytes: [0xAA])
            ),
            bytes: CashFusionOfficialProtobufFixtures.blameProofSessionKeyBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeBlameProof
        )
        try expectPrimaryPayload(
            OpalFusion.Blame.BlameProof(
                proofIndex: 1,
                decrypter: .privateKey(secretBytes: [0xBB]),
                requiresBlockchainLookup: true,
                reason: "ok"
            ),
            bytes: CashFusionOfficialProtobufFixtures.blameProofPrivateKeyWithReasonBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeBlameProof
        )
    }

    @Test("CashFusion covert payload codecs match official manual bytes")
    func validateCovertPayloadOfficialBytes() throws {
        try expectCovertPayload(
            OpalFusion.ProtocolModel.CovertComponent(
                signature: [0x30],
                serializedComponent: [0x31]
            ),
            bytes: CashFusionOfficialProtobufFixtures.covertComponentWithoutRoundKeyBytes,
            encode: OpalFusion.Wire.CashFusionCovertMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionCovertMessageCodec.decodeCovertComponent
        )
        try expectCovertPayload(
            OpalFusion.ProtocolModel.CovertTransactionSignature(
                inputIndex: 0,
                transactionSignature: [0x61]
            ),
            bytes: CashFusionOfficialProtobufFixtures.covertTransactionSignatureWithoutRoundKeyBytes,
            encode: OpalFusion.Wire.CashFusionCovertMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionCovertMessageCodec.decodeCovertTransactionSignature
        )
    }

    @Test("CashFusion primary and covert error codecs match official manual bytes")
    func validateErrorPayloadOfficialBytes() throws {
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.ServerFailure(message: "ok"),
            bytes: CashFusionOfficialProtobufFixtures.errorMessageBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerFailure
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.ServerFailure(),
            bytes: CashFusionOfficialProtobufFixtures.emptyErrorBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerFailure
        )
        try expectCovertPayload(
            OpalFusion.ProtocolModel.ServerFailure(message: "ok"),
            bytes: CashFusionOfficialProtobufFixtures.errorMessageBytes,
            encode: OpalFusion.Wire.CashFusionCovertMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionCovertMessageCodec.decodeServerFailure
        )
        try expectCovertPayload(
            OpalFusion.ProtocolModel.ServerFailure(),
            bytes: CashFusionOfficialProtobufFixtures.emptyErrorBytes,
            encode: OpalFusion.Wire.CashFusionCovertMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionCovertMessageCodec.decodeServerFailure
        )
    }
}
