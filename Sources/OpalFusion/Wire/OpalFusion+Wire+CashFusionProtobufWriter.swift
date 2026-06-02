// OpalFusion+Wire+CashFusionProtobufWriter.swift

extension OpalFusion.Wire {
    struct CashFusionProtobufWriter: Sendable {
        private var bytes: [UInt8]

        init() {
            self.bytes = []
        }

        var serializedBytes: [UInt8] {
            bytes
        }

        mutating func writeUInt64Field(
            _ value: UInt64,
            fieldNumber: Int
        ) throws {
            try writeFieldHeader(
                fieldNumber: fieldNumber,
                wireKind: .varint
            )
            writeRawVarint(value)
        }

        mutating func writeUInt32Field(
            _ value: UInt32,
            fieldNumber: Int
        ) throws {
            try writeUInt64Field(
                UInt64(value),
                fieldNumber: fieldNumber
            )
        }

        mutating func writeBoolField(
            _ value: Bool,
            fieldNumber: Int
        ) throws {
            try writeUInt64Field(
                value ? 1 : 0,
                fieldNumber: fieldNumber
            )
        }

        mutating func writeFixed32Field(
            _ value: UInt32,
            fieldNumber: Int
        ) throws {
            try writeFieldHeader(
                fieldNumber: fieldNumber,
                wireKind: .fixed32
            )
            bytes.append(UInt8(value & 0xFF))
            bytes.append(UInt8((value >> 8) & 0xFF))
            bytes.append(UInt8((value >> 16) & 0xFF))
            bytes.append(UInt8((value >> 24) & 0xFF))
        }

        mutating func writeFixed64Field(
            _ value: UInt64,
            fieldNumber: Int
        ) throws {
            try writeFieldHeader(
                fieldNumber: fieldNumber,
                wireKind: .fixed64
            )
            writeRawFixed64(value)
        }

        mutating func writePackedUInt64Field(
            _ values: [UInt64],
            fieldNumber: Int
        ) throws {
            try Self.validateFieldNumber(fieldNumber)
            guard values.isEmpty == false else {
                return
            }

            var packedBytes: [UInt8] = []
            for value in values {
                writeRawVarint(
                    value,
                    to: &packedBytes
                )
            }

            try writeBytesField(
                packedBytes,
                fieldNumber: fieldNumber
            )
        }

        mutating func writePackedUInt32Field(
            _ values: [UInt32],
            fieldNumber: Int
        ) throws {
            try writePackedUInt64Field(
                values.map(UInt64.init),
                fieldNumber: fieldNumber
            )
        }

        mutating func writeBytesField(
            _ value: [UInt8],
            fieldNumber: Int
        ) throws {
            try writeFieldHeader(
                fieldNumber: fieldNumber,
                wireKind: .lengthDelimited
            )
            writeRawVarint(UInt64(value.count))
            bytes.append(contentsOf: value)
        }

        mutating func writeStringField(
            _ value: String,
            fieldNumber: Int
        ) throws {
            try writeBytesField(
                Array(value.utf8),
                fieldNumber: fieldNumber
            )
        }
    }
}

private extension OpalFusion.Wire.CashFusionProtobufWriter {
    mutating func writeFieldHeader(
        fieldNumber: Int,
        wireKind: OpalFusion.Wire.CashFusionProtobufWireKind
    ) throws {
        try Self.validateFieldNumber(fieldNumber)
        let key = (UInt64(fieldNumber) << 3) | UInt64(wireKind.rawValue)
        writeRawVarint(key)
    }

    static func validateFieldNumber(_ fieldNumber: Int) throws {
        try OpalFusion.Wire.CashFusionProtobufFieldHeader.validateFieldNumber(
            fieldNumber
        )
    }

    mutating func writeRawVarint(_ value: UInt64) {
        writeRawVarint(
            value,
            to: &bytes
        )
    }

    func writeRawVarint(
        _ value: UInt64,
        to destination: inout [UInt8]
    ) {
        var remainingValue = value

        while remainingValue >= 0x80 {
            destination.append(UInt8(remainingValue & 0x7F) | 0x80)
            remainingValue >>= 7
        }

        destination.append(UInt8(remainingValue))
    }

    mutating func writeRawFixed64(_ value: UInt64) {
        bytes.append(UInt8(value & 0xFF))
        bytes.append(UInt8((value >> 8) & 0xFF))
        bytes.append(UInt8((value >> 16) & 0xFF))
        bytes.append(UInt8((value >> 24) & 0xFF))
        bytes.append(UInt8((value >> 32) & 0xFF))
        bytes.append(UInt8((value >> 40) & 0xFF))
        bytes.append(UInt8((value >> 48) & 0xFF))
        bytes.append(UInt8((value >> 56) & 0xFF))
    }
}
