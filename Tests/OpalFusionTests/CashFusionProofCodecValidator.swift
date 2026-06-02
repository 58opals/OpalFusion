// CashFusionProofCodecValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionProofCodecValidator {
    @Test("CashFusion proof codec matches pinned protobuf bytes")
    func validatePinnedByteParity() throws {
        let proof = OpalFusion.Blame.Proof(
            componentIndex: 0x01020304,
            salt: [0xAA, 0xBB],
            pedersenNonce: [0xCC, 0xDD]
        )
        let pinnedBytes = CashFusionPinnedProtobufFixtures.proofBytes

        #expect(try OpalFusion.Wire.CashFusionProofCodec.encode(proof) == pinnedBytes)
        #expect(try OpalFusion.Wire.CashFusionProofCodec.decode(pinnedBytes) == proof)
    }

    @Test("CashFusion proof codec rejects invalid schema bytes")
    func validateSchemaFailures() {
        Self.expectCodingError(.missingRequiredField(messageName: "Proof", fieldNumber: 2)) {
            _ = try OpalFusion.Wire.CashFusionProofCodec.decode([
                0x0D, 0x04, 0x03, 0x02, 0x01
            ])
        }

        Self.expectCodingError(.wireKindMismatch(expected: .fixed32, actual: .varint)) {
            _ = try OpalFusion.Wire.CashFusionProofCodec.decode([0x08, 0x01])
        }
    }

    @Test("CashFusion proof codec skips unknown fields")
    func validateUnknownFieldSkipping() throws {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeStringField("ignored", fieldNumber: 12)
        let proof = OpalFusion.Blame.Proof(
            componentIndex: 1,
            salt: [0x02],
            pedersenNonce: [0x03]
        )

        #expect(
            try OpalFusion.Wire.CashFusionProofCodec.decode(
                writer.serializedBytes + OpalFusion.Wire.CashFusionProofCodec.encode(proof)
            ) == proof
        )
    }
}

extension CashFusionProofCodecValidator {
    static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
