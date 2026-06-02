// CashFusionPrimaryMessageCodecValidator+OfficialEdgeFixtures.swift

@testable import OpalFusion
import Testing

extension CashFusionPrimaryMessageCodecValidator {
    @Test("CashFusion primary codec accepts official repeated and map edge bytes")
    func validateOfficialRepeatedAndMapEdgeBytes() throws {
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
                CashFusionOfficialProtobufFixtures.serverHelloUnpackedTiersBytes
            ) == serverHello
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
                CashFusionOfficialProtobufFixtures.fusionResultUnpackedBadComponentsBytes
            ) == fusionResult
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeFusionResult(
                CashFusionOfficialProtobufFixtures.fusionResultPackedBadComponentsBytes
            ) == fusionResult
        )

        let lastWinsTierStatusUpdate = OpalFusion.ProtocolModel.TierStatusUpdate(
            statusesByTier: [
                1: .init(minimumPlayerCount: 2)
            ]
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeTierStatusUpdate(
                CashFusionOfficialProtobufFixtures.tierStatusDuplicateMapKeyBytes
            ) == lastWinsTierStatusUpdate
        )
        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(lastWinsTierStatusUpdate)
                == CashFusionOfficialProtobufFixtures.tierStatusLastWinsMapKeyBytes
        )
    }

    @Test("CashFusion primary codec rejects malformed envelopes explicitly")
    func validateMalformedPrimaryMessages() throws {
        Self.expectPrimaryError(.missingClientMessageCase) {
            _ = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClient([])
        }

        Self.expectPrimaryError(.missingServerMessageCase) {
            _ = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer([])
        }

        Self.expectPrimaryError(.missingBlameDecrypter) {
            _ = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClient(
                Self.makeClientBlamesEnvelopeWithoutDecrypter()
            )
        }

        Self.expectCodingError(
            .conflictingOneOfField(
                messageName: "ClientMessage",
                fieldNumber: 2
            )
        ) {
            _ = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClient(
                Self.makeConflictingClientEnvelope()
            )
        }

        Self.expectPrimaryError(.invalidUTF8Field("FusionBegin.covertDomain")) {
            _ = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer(
                Self.makeServerFusionBeginEnvelopeWithInvalidDomain()
            )
        }

        Self.expectPrimaryError(.invalidUTF8Field("Error.message")) {
            _ = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer(
                Self.makeServerFailureEnvelopeWithInvalidMessage()
            )
        }

        Self.expectCodingError(
            .lengthDelimitedValueOutOfBounds(
                length: 2,
                remainingByteCount: 1
            )
        ) {
            _ = try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer(
                CashFusionOfficialProtobufFixtures.malformedServerEnvelopeLengthBytes
            )
        }
    }

    @Test("CashFusion primary codec skips unknown envelope fields")
    func validateUnknownEnvelopeFields() throws {
        let message = OpalFusion.ProtocolModel.ServerMessage.serverHello(
            .init(
                tiers: [],
                numberOfComponents: 0,
                componentFeeRateSatoshisPerKb: 0,
                minimumExcessFeeSatoshis: 0,
                maximumExcessFeeSatoshis: 0
            )
        )

        #expect(
            try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer(
                CashFusionOfficialProtobufFixtures.serverHelloEnvelopeWithUnknownPrefixBytes
            ) == message
        )
    }
}
