// CashFusionInitialCommitmentCodecValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionInitialCommitmentCodecValidator {
    @Test("CashFusion initial commitment codec matches pinned protobuf bytes")
    func validatePinnedByteParity() throws {
        let commitment = OpalFusion.Commitment.InitialCommitment(
            saltedComponentHash: [0x01, 0x02],
            amountCommitment: [0x03, 0x04],
            communicationPublicKey: [0x05, 0x06]
        )
        let pinnedBytes = CashFusionPinnedProtobufFixtures.initialCommitmentBytes

        #expect(
            try OpalFusion.Wire.CashFusionInitialCommitmentCodec.encode(commitment)
                == pinnedBytes
        )
        #expect(
            try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode(pinnedBytes)
                == commitment
        )
    }

    @Test("CashFusion initial commitment codec rejects invalid schema bytes")
    func validateSchemaFailures() {
        Self.expectCodingError(.missingRequiredField(messageName: "InitialCommitment", fieldNumber: 2)) {
            _ = try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode([0x0A, 0x01, 0x01])
        }

        Self.expectCodingError(.wireKindMismatch(expected: .lengthDelimited, actual: .varint)) {
            _ = try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode([0x08, 0x01])
        }
    }

    @Test("CashFusion initial commitment codec skips unknown fields")
    func validateUnknownFieldSkipping() throws {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt64Field(7, fieldNumber: 9)
        let prefixedBytes = writer.serializedBytes
            + (try OpalFusion.Wire.CashFusionInitialCommitmentCodec.encode(
                .init(
                    saltedComponentHash: [0x01],
                    amountCommitment: [0x02],
                    communicationPublicKey: [0x03]
                )
            ))

        #expect(
            try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode(prefixedBytes)
                == .init(
                    saltedComponentHash: [0x01],
                    amountCommitment: [0x02],
                    communicationPublicKey: [0x03]
                )
        )
    }
}

extension CashFusionInitialCommitmentCodecValidator {
    static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
