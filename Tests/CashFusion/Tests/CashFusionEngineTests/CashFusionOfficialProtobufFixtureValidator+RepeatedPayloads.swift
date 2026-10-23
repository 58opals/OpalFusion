// CashFusionOfficialProtobufFixtureValidator+RepeatedPayloads.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Testing

extension CashFusionOfficialProtobufFixtureValidator {
    @Test("CashFusion repeated-only payload codecs match official empty bytes")
    func validateEmptyRepeatedPayloadOfficialBytes() throws {
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.JoinPools(
                tiers: [],
                tags: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.joinPoolsEmptyBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeJoinPools
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.BlindSignatureResponses(
                responses: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.blindSigResponsesEmptyBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeBlindSignatureResponses
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.AllCommitments(
                initialCommitments: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.allCommitmentsEmptyBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeAllCommitments
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.ShareCovertComponents(
                serializedComponents: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.shareCovertComponentsEmptyBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeShareCovertComponents
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.TheirProofsList(
                proofs: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.theirProofsListEmptyBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeTheirProofsList
        )
    }
}
