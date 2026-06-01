// OpalFusion+Wire+CashFusionProtobufReader.swift

#if canImport(FoundationEssentials)
import FoundationEssentials
#else
import Foundation
#endif

extension OpalFusion.Wire {
    struct CashFusionProtobufReader: Sendable {
        private let bytes: [UInt8]
        private var cursor: Int

        init(bytes: [UInt8]) {
            self.bytes = bytes
            self.cursor = 0
        }

        var isAtEnd: Bool {
            cursor >= bytes.count
        }

        mutating func nextFieldHeader() throws -> OpalFusion.Wire.CashFusionProtobufFieldHeader? {
            guard isAtEnd == false else {
                return nil
            }

            let key = try readRawVarint()
            let fieldNumber = Int(key >> 3)
            let wireKind = try OpalFusion.Wire.CashFusionProtobufWireKind(
                rawWireKind: key & 0x07
            )
            return try .init(
                number: fieldNumber,
                wireKind: wireKind
            )
        }

        mutating func readUInt64Value(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> UInt64 {
            try requireWireKind(.varint, for: fieldHeader)
            return try readRawVarint()
        }

        mutating func readUInt32Value(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> UInt32 {
            let value = try readUInt64Value(for: fieldHeader)
            guard value <= UInt64(UInt32.max) else {
                throw OpalFusion.Wire.CashFusionProtobufCodingError.uint32ValueOutOfRange(
                    value
                )
            }
            return UInt32(value)
        }

        mutating func readBoolValue(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> Bool {
            try readUInt64Value(for: fieldHeader) != 0
        }

        mutating func readFixed32Value(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> UInt32 {
            try requireWireKind(.fixed32, for: fieldHeader)
            return try readRawFixed32()
        }

        mutating func readFixed64Value(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> UInt64 {
            try requireWireKind(.fixed64, for: fieldHeader)
            return try readRawFixed64()
        }

        mutating func readBytesValue(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> [UInt8] {
            try requireWireKind(.lengthDelimited, for: fieldHeader)
            let length = try readRawVarint()
            guard length <= UInt64(Int.max) else {
                throw OpalFusion.Wire.CashFusionProtobufCodingError
                    .lengthDelimitedValueOutOfBounds(
                        length: length,
                        remainingByteCount: bytes.count - cursor
                    )
            }

            let byteCount = Int(length)
            guard byteCount <= bytes.count - cursor else {
                throw OpalFusion.Wire.CashFusionProtobufCodingError
                    .lengthDelimitedValueOutOfBounds(
                        length: length,
                        remainingByteCount: bytes.count - cursor
                    )
            }

            let value = Array(bytes[cursor..<(cursor + byteCount)])
            cursor += byteCount
            return value
        }

        mutating func readStringValue(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> String {
            let value = try readBytesValue(for: fieldHeader)
            guard let string = String(bytes: value, encoding: .utf8) else {
                throw OpalFusion.Wire.CashFusionProtobufCodingError.invalidUTF8String
            }
            return string
        }

        mutating func skipValue(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws {
            switch fieldHeader.wireKind {
            case .varint:
                _ = try readRawVarint()
            case .fixed64:
                try skipFixedByteCount(8)
            case .lengthDelimited:
                _ = try readBytesValue(for: fieldHeader)
            case .fixed32:
                try skipFixedByteCount(4)
            }
        }
    }
}

extension OpalFusion.Wire.CashFusionProtobufReader {
    mutating func requireWireKind(
        _ expectedWireKind: OpalFusion.Wire.CashFusionProtobufWireKind,
        for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
    ) throws {
        guard fieldHeader.wireKind == expectedWireKind else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.wireKindMismatch(
                expected: expectedWireKind,
                actual: fieldHeader.wireKind
            )
        }
    }

    mutating func readRawVarint() throws -> UInt64 {
        var value: UInt64 = 0

        for byteIndex in 0..<10 {
            guard isAtEnd == false else {
                throw OpalFusion.Wire.CashFusionProtobufCodingError.truncatedInput
            }

            let byte = bytes[cursor]
            cursor += 1

            if byteIndex == 9, byte > 0x01 {
                throw OpalFusion.Wire.CashFusionProtobufCodingError.varintOverflow
            }

            value |= UInt64(byte & 0x7F) << UInt64(byteIndex * 7)

            if byte < 0x80 {
                return value
            }
        }

        throw OpalFusion.Wire.CashFusionProtobufCodingError.varintOverflow
    }

    mutating func skipFixedByteCount(_ byteCount: Int) throws {
        guard byteCount <= bytes.count - cursor else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.truncatedInput
        }
        cursor += byteCount
    }

    mutating func readRawFixed32() throws -> UInt32 {
        guard 4 <= bytes.count - cursor else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.truncatedInput
        }

        let value = UInt32(bytes[cursor])
            | (UInt32(bytes[cursor + 1]) << 8)
            | (UInt32(bytes[cursor + 2]) << 16)
            | (UInt32(bytes[cursor + 3]) << 24)
        cursor += 4
        return value
    }

    mutating func readRawFixed64() throws -> UInt64 {
        guard 8 <= bytes.count - cursor else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.truncatedInput
        }

        let value = UInt64(bytes[cursor])
            | (UInt64(bytes[cursor + 1]) << 8)
            | (UInt64(bytes[cursor + 2]) << 16)
            | (UInt64(bytes[cursor + 3]) << 24)
            | (UInt64(bytes[cursor + 4]) << 32)
            | (UInt64(bytes[cursor + 5]) << 40)
            | (UInt64(bytes[cursor + 6]) << 48)
            | (UInt64(bytes[cursor + 7]) << 56)
        cursor += 8
        return value
    }
}
