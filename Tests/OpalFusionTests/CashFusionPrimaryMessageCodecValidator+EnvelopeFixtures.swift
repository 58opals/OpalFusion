// CashFusionPrimaryMessageCodecValidator+EnvelopeFixtures.swift

@testable import OpalFusion
import Testing

extension CashFusionPrimaryMessageCodecValidator {
    static func makeClientBlamesEnvelopeWithoutDecrypter() throws -> [UInt8] {
        var proofWriter = OpalFusion.Wire.CashFusionProtobufWriter()
        try proofWriter.writeUInt32Field(
            1,
            fieldNumber: 1
        )

        var blamesWriter = OpalFusion.Wire.CashFusionProtobufWriter()
        try blamesWriter.writeBytesField(
            proofWriter.serializedBytes,
            fieldNumber: 1
        )

        var envelopeWriter = OpalFusion.Wire.CashFusionProtobufWriter()
        try envelopeWriter.writeBytesField(
            blamesWriter.serializedBytes,
            fieldNumber: 6
        )
        return envelopeWriter.serializedBytes
    }

    static func makeConflictingClientEnvelope() throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            [],
            fieldNumber: 1
        )
        try writer.writeBytesField(
            [],
            fieldNumber: 2
        )
        return writer.serializedBytes
    }

    static func makeServerFusionBeginEnvelopeWithInvalidDomain() throws -> [UInt8] {
        var fusionBeginWriter = OpalFusion.Wire.CashFusionProtobufWriter()
        try fusionBeginWriter.writeBytesField(
            [0xFF],
            fieldNumber: 2
        )

        var envelopeWriter = OpalFusion.Wire.CashFusionProtobufWriter()
        try envelopeWriter.writeBytesField(
            fusionBeginWriter.serializedBytes,
            fieldNumber: 3
        )
        return envelopeWriter.serializedBytes
    }

    static func makeServerFailureEnvelopeWithInvalidMessage() throws -> [UInt8] {
        var failureWriter = OpalFusion.Wire.CashFusionProtobufWriter()
        try failureWriter.writeBytesField(
            [0xFF],
            fieldNumber: 1
        )

        var envelopeWriter = OpalFusion.Wire.CashFusionProtobufWriter()
        try envelopeWriter.writeBytesField(
            failureWriter.serializedBytes,
            fieldNumber: 15
        )
        return envelopeWriter.serializedBytes
    }

    static func expectPrimaryError<Success>(
        _ expectedError: OpalFusion.Wire.PrimaryMessageCodecError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }

    static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
