// CashFusionOfficialProtobufFixtureValidator+RepeatedPayloads.swift

@testable import OpalFusion
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

    @Test("CashFusion repeated and map payload codecs match official edge bytes")
    func validateRepeatedAndMapPayloadOfficialBytes() throws {
        let serverHello = OpalFusion.ProtocolModel.ServerHello(
            tiers: [1, 300],
            numberOfComponents: 0,
            componentFeeRateSatoshisPerKb: 0,
            minimumExcessFeeSatoshis: 0,
            maximumExcessFeeSatoshis: 0
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(serverHello)
                == CashFusionOfficialProtobufFixtures.serverHelloUnpackedTiersBytes
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerHello(
                CashFusionOfficialProtobufFixtures.serverHelloPackedTiersBytes
            ) == serverHello
        )

        let fusionResult = OpalFusion.ProtocolModel.FusionResult(
            isSuccess: false,
            transactionSignatures: [],
            badComponentIndices: [1, 300]
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(fusionResult)
                == CashFusionOfficialProtobufFixtures.fusionResultUnpackedBadComponentsBytes
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionResult(
                CashFusionOfficialProtobufFixtures.fusionResultPackedBadComponentsBytes
            ) == fusionResult
        )

        let tierStatusUpdate = OpalFusion.ProtocolModel.TierStatusUpdate(
            statusesByTier: [
                1: .init(minimumPlayerCount: 2)
            ]
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeTierStatusUpdate(
                CashFusionOfficialProtobufFixtures.tierStatusDuplicateMapKeyBytes
            ) == tierStatusUpdate
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(tierStatusUpdate)
                == CashFusionOfficialProtobufFixtures.tierStatusLastWinsMapKeyBytes
        )
    }
}
