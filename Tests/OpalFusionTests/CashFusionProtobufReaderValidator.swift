// CashFusionProtobufReaderValidator.swift

@testable import OpalFusion
import Testing

struct CashFusionProtobufReaderValidator {
    @Test("CashFusion protobuf reader parses typed primitive fields")
    func validateTypedPrimitiveFields() throws {
        let payload: [UInt8] = [
            0x08, 0x96, 0x01,
            0x28, 0xAC, 0x02,
            0x35, 0x04, 0x03, 0x02, 0x01,
            0x39, 0x08, 0x07, 0x06, 0x05, 0x04, 0x03, 0x02, 0x01,
            0x4A, 0x03, 0x01, 0xAC, 0x02,
            0x12, 0x02, 0xAA, 0xBB,
            0x18, 0x01,
            0x22, 0x05, 0x61, 0x6C, 0x70, 0x68, 0x61
        ]
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: payload)

        let integerHeader = try #require(try reader.nextFieldHeader())
        #expect(integerHeader.number == 1)
        #expect(integerHeader.wireKind == .varint)
        #expect(try reader.readUInt64Value(for: integerHeader) == 150)

        let uint32Header = try #require(try reader.nextFieldHeader())
        #expect(uint32Header.number == 5)
        #expect(uint32Header.wireKind == .varint)
        #expect(try reader.readUInt32Value(for: uint32Header) == 300)

        let fixed32Header = try #require(try reader.nextFieldHeader())
        #expect(fixed32Header.number == 6)
        #expect(fixed32Header.wireKind == .fixed32)
        #expect(try reader.readFixed32Value(for: fixed32Header) == 0x01020304)

        let fixed64Header = try #require(try reader.nextFieldHeader())
        #expect(fixed64Header.number == 7)
        #expect(fixed64Header.wireKind == .fixed64)
        #expect(try reader.readFixed64Value(for: fixed64Header) == 0x0102030405060708)

        let packedHeader = try #require(try reader.nextFieldHeader())
        #expect(packedHeader.number == 9)
        #expect(packedHeader.wireKind == .lengthDelimited)
        #expect(try reader.readRepeatedUInt32Values(for: packedHeader) == [1, 300])

        let bytesHeader = try #require(try reader.nextFieldHeader())
        #expect(bytesHeader.number == 2)
        #expect(bytesHeader.wireKind == .lengthDelimited)
        #expect(try reader.readBytesValue(for: bytesHeader) == [0xAA, 0xBB])

        let boolHeader = try #require(try reader.nextFieldHeader())
        #expect(boolHeader.number == 3)
        #expect(boolHeader.wireKind == .varint)
        #expect(try reader.readBoolValue(for: boolHeader))

        let stringHeader = try #require(try reader.nextFieldHeader())
        #expect(stringHeader.number == 4)
        #expect(stringHeader.wireKind == .lengthDelimited)
        #expect(try reader.readStringValue(for: stringHeader) == "alpha")
        #expect(reader.isAtEnd)
        #expect(try reader.nextFieldHeader() == nil)
    }

    @Test("CashFusion protobuf reader skips supported unknown field kinds")
    func validateUnknownFieldSkipping() throws {
        let payload: [UInt8] = [
            0x08, 0x96, 0x01,
            0x11, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
            0x1A, 0x02, 0xAA, 0xBB,
            0x25, 0x09, 0x0A, 0x0B, 0x0C,
            0x28, 0x07
        ]
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: payload)

        for _ in 0..<4 {
            let fieldHeader = try #require(try reader.nextFieldHeader())
            try reader.skipValue(for: fieldHeader)
        }

        let finalHeader = try #require(try reader.nextFieldHeader())
        #expect(finalHeader.number == 5)
        #expect(try reader.readUInt64Value(for: finalHeader) == 7)
        #expect(reader.isAtEnd)
    }

    @Test("CashFusion protobuf reader rejects invalid field headers")
    func validateInvalidFieldHeaders() {
        Self.expectCodingError(.invalidFieldNumber(0)) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: [0x00])
            _ = try reader.nextFieldHeader()
        }

        Self.expectCodingError(.invalidWireKind(3)) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: [0x0B])
            _ = try reader.nextFieldHeader()
        }
    }

    @Test("CashFusion protobuf reader rejects malformed primitive values")
    func validateMalformedPrimitiveValues() throws {
        Self.expectCodingError(.varintOverflow) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(
                bytes: [0x08] + Array(repeating: 0x80, count: 10)
            )
            let fieldHeader = try #require(try reader.nextFieldHeader())
            _ = try reader.readUInt64Value(for: fieldHeader)
        }

        Self.expectCodingError(.truncatedInput) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: [0x08, 0x80])
            let fieldHeader = try #require(try reader.nextFieldHeader())
            _ = try reader.readUInt64Value(for: fieldHeader)
        }

        Self.expectCodingError(.lengthDelimitedValueOutOfBounds(length: 3, remainingByteCount: 1)) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: [0x0A, 0x03, 0xAA])
            let fieldHeader = try #require(try reader.nextFieldHeader())
            _ = try reader.readBytesValue(for: fieldHeader)
        }

        Self.expectCodingError(.uint32ValueOutOfRange(4_294_967_296)) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(
                bytes: [0x08, 0x80, 0x80, 0x80, 0x80, 0x10]
            )
            let fieldHeader = try #require(try reader.nextFieldHeader())
            _ = try reader.readUInt32Value(for: fieldHeader)
        }

        let lengthDelimitedHeader = try OpalFusion.Wire.CashFusionProtobufFieldHeader(
            number: 1,
            wireKind: .lengthDelimited
        )
        Self.expectCodingError(.wireKindMismatch(expected: .varint, actual: .lengthDelimited)) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: [0x00])
            _ = try reader.readUInt64Value(for: lengthDelimitedHeader)
        }

        Self.expectCodingError(.invalidUTF8String) {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: [0x0A, 0x01, 0xFF])
            let fieldHeader = try #require(try reader.nextFieldHeader())
            _ = try reader.readStringValue(for: fieldHeader)
        }
    }
}

private extension CashFusionProtobufReaderValidator {
    static func expectCodingError<Success>(
        _ expectedError: OpalFusion.Wire.CashFusionProtobufCodingError,
        from operation: () throws -> Success
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }
}
