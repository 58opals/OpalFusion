// CashFusionCovertMessageCodecValidator+EnvelopeFixtures.swift

@testable import OpalFusion
import Testing

extension CashFusionCovertMessageCodecValidator {
    static func makeConflictingCovertEnvelope() throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            [],
            fieldNumber: 1
        )
        try writer.writeBytesField(
            [],
            fieldNumber: 3
        )
        return writer.serializedBytes
    }

    static func makeConflictingCovertResponseEnvelope() throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            [],
            fieldNumber: 1
        )
        try writer.writeBytesField(
            [],
            fieldNumber: 15
        )
        return writer.serializedBytes
    }

    static func makeCovertFailureEnvelopeWithInvalidMessage() throws -> [UInt8] {
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

    static func expectCovertError<Success>(
        _ expectedError: OpalFusion.Wire.CovertMessageCodecError,
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
