// CashFusionOfficialProtobufFixtureValidator+PrimaryPayloads.swift

@testable import OpalFusion
import Testing

extension CashFusionOfficialProtobufFixtureValidator {
    @Test("CashFusion primary payload codecs match official manual required-field bytes")
    func validatePrimaryPayloadOfficialBytes() throws {
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.ClientHello(versionBytes: []),
            bytes: CashFusionOfficialProtobufFixtures.clientHelloEmptyVersionBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClientHello
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.ServerHello(
                tiers: [],
                numberOfComponents: 0,
                componentFeeRateSatoshisPerKb: 0,
                minimumExcessFeeSatoshis: 0,
                maximumExcessFeeSatoshis: 0
            ),
            bytes: CashFusionOfficialProtobufFixtures.serverHelloRequiredZeroBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServerHello
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.PoolTag(identifier: [], limit: 0),
            bytes: CashFusionOfficialProtobufFixtures.poolTagRequiredZeroBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePoolTag
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.FusionBegin(
                tier: 0,
                covertDomain: "",
                covertPort: 0,
                serverTimeUnixSeconds: 0
            ),
            bytes: CashFusionOfficialProtobufFixtures.fusionBeginRequiredZeroBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionBegin
        )
    }

    @Test("CashFusion round and result payload codecs match official manual bytes")
    func validateRoundPayloadOfficialBytes() throws {
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.StartRound(
                roundPublicKey: [],
                blindNoncePoints: [],
                serverTimeUnixSeconds: 0
            ),
            bytes: CashFusionOfficialProtobufFixtures.startRoundRequiredZeroBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeStartRound
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.PlayerCommit(
                initialCommitments: [],
                excessFeeSatoshis: 0,
                pedersenTotalNonce: [],
                randomNumberCommitment: [],
                blindSignatureRequests: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.playerCommitRequiredZeroBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodePlayerCommit
        )
        try expectPrimaryPayload(
            OpalFusion.ProtocolModel.FusionResult(
                isSuccess: false,
                transactionSignatures: [],
                badComponentIndices: []
            ),
            bytes: CashFusionOfficialProtobufFixtures.fusionResultRequiredFalseBytes,
            encode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode,
            decode: OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionResult
        )
    }
}
