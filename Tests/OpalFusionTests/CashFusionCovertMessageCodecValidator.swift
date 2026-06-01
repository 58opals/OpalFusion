// CashFusionCovertMessageCodecValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionCovertMessageCodecValidator {
    @Test("CashFusion covert codec matches pinned message bytes")
    func validateCovertMessagePinnedByteParity() throws {
        #expect(
            PrimaryRuntimeTestFixtures.covertMessages.count
                == CashFusionPinnedProtobufFixtures.covertMessageBytes.count
        )

        for (message, pinnedBytes) in zip(
            PrimaryRuntimeTestFixtures.covertMessages,
            CashFusionPinnedProtobufFixtures.covertMessageBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionCovertMessageCodec.encode(message)

            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeMessage(
                    pinnedBytes
                ) == message
            )
        }
    }

    @Test("CashFusion covert codec matches pinned response bytes")
    func validateCovertResponsePinnedByteParity() throws {
        #expect(
            PrimaryRuntimeTestFixtures.covertResponses.count
                == CashFusionPinnedProtobufFixtures.covertResponseBytes.count
        )

        for (response, pinnedBytes) in zip(
            PrimaryRuntimeTestFixtures.covertResponses,
            CashFusionPinnedProtobufFixtures.covertResponseBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionCovertMessageCodec.encode(response)

            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeResponse(
                    pinnedBytes
                ) == response
            )
        }
    }

    @Test("CashFusion covert codec handles absent optional fields")
    func validateOptionalFieldParity() throws {
        let messages: [OpalFusion.ProtocolModel.CovertMessage] = [
            .component(
                .init(
                    roundPublicKey: nil,
                    signature: [0x01],
                    serializedComponent: [0x02]
                )
            ),
            .transactionSignature(
                .init(
                    roundPublicKey: nil,
                    inputIndex: 1,
                    transactionSignature: [0x03]
                )
            )
        ]
        let responses: [OpalFusion.ProtocolModel.CovertResponse] = [
            .serverFailure(.init(message: nil))
        ]

        #expect(
            messages.count
                == CashFusionPinnedProtobufFixtures.covertOptionalMessageBytes.count
        )
        #expect(
            responses.count
                == CashFusionPinnedProtobufFixtures.covertOptionalResponseBytes.count
        )

        for (message, pinnedBytes) in zip(
            messages,
            CashFusionPinnedProtobufFixtures.covertOptionalMessageBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionCovertMessageCodec.encode(message)
            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeMessage(
                    pinnedBytes
                ) == message
            )
        }

        for (response, pinnedBytes) in zip(
            responses,
            CashFusionPinnedProtobufFixtures.covertOptionalResponseBytes
        ) {
            let nativeBytes = try OpalFusion.Wire.CashFusionCovertMessageCodec.encode(response)
            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeResponse(
                    pinnedBytes
                ) == response
            )
        }
    }

    @Test("CashFusion covert codec rejects malformed envelopes explicitly")
    func validateMalformedCovertMessages() throws {
        Self.expectCovertError(.missingCovertMessageCase) {
            _ = try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeMessage([])
        }

        Self.expectCovertError(.missingCovertResponseCase) {
            _ = try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeResponse([])
        }

        Self.expectCodingError(
            .conflictingOneOfField(
                messageName: "CovertMessage",
                fieldNumber: 3
            )
        ) {
            _ = try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeMessage(
                Self.makeConflictingCovertEnvelope()
            )
        }

        Self.expectCodingError(
            .conflictingOneOfField(
                messageName: "CovertResponse",
                fieldNumber: 15
            )
        ) {
            _ = try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeResponse(
                Self.makeConflictingCovertResponseEnvelope()
            )
        }

        Self.expectCodingError(.invalidUTF8String) {
            _ = try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeResponse(
                Self.makeCovertFailureEnvelopeWithInvalidMessage()
            )
        }

        Self.expectCodingError(.truncatedInput) {
            _ = try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeResponse(
                [0x7A, 0x01, 0x0A]
            )
        }
    }

    @Test("CashFusion covert codec skips unknown envelope fields")
    func validateUnknownEnvelopeFields() throws {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt64Field(
            1,
            fieldNumber: 99
        )
        let message = PrimaryRuntimeTestFixtures.covertComponentMessage
        let payload = writer.serializedBytes
            + (try OpalFusion.Wire.CashFusionCovertMessageCodec.encode(message))

        #expect(
            try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeMessage(
                payload
            ) == message
        )
    }
}
