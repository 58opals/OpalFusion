// CashFusionProtobufWriterValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionProtobufWriterValidator {
    @Test("CashFusion protobuf writer encodes canonical primitive fields")
    func validateCanonicalPrimitiveFields() throws {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()

        try writer.writeUInt64Field(
            150,
            fieldNumber: 1
        )
        try writer.writeUInt32Field(
            300,
            fieldNumber: 2
        )
        try writer.writeBoolField(
            true,
            fieldNumber: 3
        )
        try writer.writeFixed32Field(
            0x01020304,
            fieldNumber: 6
        )
        try writer.writeFixed64Field(
            0x0102030405060708,
            fieldNumber: 7
        )
        try writer.writePackedUInt32Field(
            [1, 300],
            fieldNumber: 8
        )
        try writer.writeBytesField(
            [0xAA, 0xBB],
            fieldNumber: 4
        )
        try writer.writeStringField(
            "ok",
            fieldNumber: 5
        )

        #expect(
            writer.serializedBytes == [
                0x08, 0x96, 0x01,
                0x10, 0xAC, 0x02,
                0x18, 0x01,
                0x35, 0x04, 0x03, 0x02, 0x01,
                0x39, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
                0x42, 0x03, 0x01, 0xAC, 0x02,
                0x22, 0x02, 0xAA, 0xBB,
                0x2A, 0x02, 0x6F, 0x6B
            ]
        )
    }

    @Test("CashFusion protobuf writer encodes canonical maximum UInt64 varints")
    func validateMaximumUInt64Varint() throws {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()

        try writer.writeUInt64Field(
            UInt64.max,
            fieldNumber: 1
        )

        #expect(
            writer.serializedBytes == [
                0x08,
                0xFF, 0xFF, 0xFF, 0xFF, 0xFF,
                0xFF, 0xFF, 0xFF, 0xFF, 0x01
            ]
        )
    }

    @Test("CashFusion protobuf writer omits empty packed repeated fields")
    func validateEmptyPackedRepeatedFields() throws {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()

        try writer.writePackedUInt32Field(
            [],
            fieldNumber: 8
        )
        try writer.writePackedUInt64Field(
            [],
            fieldNumber: 9
        )

        #expect(writer.serializedBytes.isEmpty)
    }

    @Test("CashFusion protobuf writer rejects invalid field numbers")
    func validateInvalidFieldNumbers() {
        Self.expectCodingError(.invalidFieldNumber(0)) {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeUInt64Field(
                1,
                fieldNumber: 0
            )
        }

        Self.expectCodingError(.invalidFieldNumber(536_870_912)) {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeBytesField(
                [],
                fieldNumber: 536_870_912
            )
        }

        Self.expectCodingError(.invalidFieldNumber(0)) {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writePackedUInt32Field(
                [],
                fieldNumber: 0
            )
        }
    }
}

extension CashFusionProtobufWriterValidator {
    static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
