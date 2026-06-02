// CashFusionComponentCodecValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionComponentCodecValidator {
    @Test("CashFusion component codec matches pinned input bytes")
    func validateInputPinnedByteParity() throws {
        let payload = Self.inputPayload
        let nativeBytes = try OpalFusion.Wire.CashFusionComponentCodec.encode(
            payload: payload,
            saltCommitment: Self.saltCommitment
        )
        let pinnedBytes = CashFusionPinnedProtobufFixtures.componentInputBytes

        #expect(nativeBytes == pinnedBytes)
        #expect(
            try OpalFusion.Wire.CashFusionComponentCodec.decode(nativeBytes)
                == .init(saltCommitment: Self.saltCommitment, payload: payload)
        )
    }

    @Test("CashFusion component codec matches pinned output and blank bytes")
    func validateOutputAndBlankPinnedByteParity() throws {
        let cases: [(OpalFusion.Commitment.ComponentPayload, [UInt8])] = [
            (Self.outputPayload, CashFusionPinnedProtobufFixtures.componentOutputBytes),
            (Self.blankPayload, CashFusionPinnedProtobufFixtures.componentBlankBytes)
        ]

        for (payload, pinnedBytes) in cases {
            let nativeBytes = try OpalFusion.Wire.CashFusionComponentCodec.encode(
                payload: payload,
                saltCommitment: Self.saltCommitment
            )

            #expect(nativeBytes == pinnedBytes)
            #expect(
                try OpalFusion.Wire.CashFusionComponentCodec.decode(nativeBytes)
                    == .init(saltCommitment: Self.saltCommitment, payload: payload)
            )
        }
    }

    @Test("CashFusion component codec rejects malformed schema bytes")
    func validateSchemaFailures() throws {
        Self.expectCodingError(.missingRequiredField(messageName: "Component", fieldNumber: 1)) {
            _ = try OpalFusion.Wire.CashFusionComponentCodec.decode([0x22, 0x00])
        }

        Self.expectCodingError(.conflictingOneOfField(messageName: "Component", fieldNumber: 2)) {
            let validBytes = try OpalFusion.Wire.CashFusionComponentCodec.encode(
                payload: Self.inputPayload,
                saltCommitment: Self.saltCommitment
            )
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeBytesField(
                CashFusionPinnedProtobufFixtures.componentInputPayloadBytes,
                fieldNumber: 2
            )
            _ = try OpalFusion.Wire.CashFusionComponentCodec.decode(
                validBytes + writer.serializedBytes
            )
        }

        Self.expectCodingError(.truncatedInput) {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeBytesField(Self.saltCommitment, fieldNumber: 1)
            try writer.writeBytesField([0x0A], fieldNumber: 2)
            _ = try OpalFusion.Wire.CashFusionComponentCodec.decode(writer.serializedBytes)
        }
    }

    @Test("CashFusion component codec rejects conflicting oneof before malformed second payload")
    func validateMalformedSecondOneOfPayloadConflict() throws {
        Self.expectCodingError(.conflictingOneOfField(messageName: "Component", fieldNumber: 2)) {
            let validBytes = try OpalFusion.Wire.CashFusionComponentCodec.encode(
                payload: Self.inputPayload,
                saltCommitment: Self.saltCommitment
            )
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeBytesField(
                [0x0A],
                fieldNumber: 2
            )
            _ = try OpalFusion.Wire.CashFusionComponentCodec.decode(
                validBytes + writer.serializedBytes
            )
        }
    }

    @Test("CashFusion component codec skips unknown fields")
    func validateUnknownFieldSkipping() throws {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt64Field(99, fieldNumber: 12)
        let componentBytes = try OpalFusion.Wire.CashFusionComponentCodec.encode(
            payload: Self.outputPayload,
            saltCommitment: Self.saltCommitment
        )

        #expect(
            try OpalFusion.Wire.CashFusionComponentCodec.decode(
                writer.serializedBytes + componentBytes
            ) == .init(saltCommitment: Self.saltCommitment, payload: Self.outputPayload)
        )
    }
}

extension CashFusionComponentCodecValidator {
    static let saltCommitment = [UInt8](repeating: 0xAB, count: 32)
    static let inputPayload = OpalFusion.Commitment.ComponentPayload.input(
        .init(
            outpointTransactionHash: [0x01, 0x02, 0x03, 0x04],
            outpointIndex: 2,
            publicKey: [0x02, 0xAA, 0xBB],
            amountSatoshis: 5_000
        )
    )
    static let outputPayload = OpalFusion.Commitment.ComponentPayload.output(
        .init(lockingScript: [0x51], amountSatoshis: 4_000)
    )
    static let blankPayload = OpalFusion.Commitment.ComponentPayload.blank(.init())

    static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
