// OpalFusion+Wire+CashFusionProtobufReader+RepeatedValues.swift

extension OpalFusion.Wire.CashFusionProtobufReader {
        mutating func readRepeatedUInt64Values(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> [UInt64] {
            switch fieldHeader.wireKind {
            case .varint:
                return [try readUInt64Value(for: fieldHeader)]
            case .lengthDelimited:
                let packedBytes = try readBytesValue(for: fieldHeader)
                var packedReader = OpalFusion.Wire.CashFusionProtobufReader(
                    bytes: packedBytes
                )
                var values: [UInt64] = []
                while packedReader.isAtEnd == false {
                    values.append(try packedReader.readRawVarint())
                }
                return values
            case .fixed32, .fixed64:
                throw OpalFusion.Wire.CashFusionProtobufCodingError.wireKindMismatch(
                    expected: .lengthDelimited,
                    actual: fieldHeader.wireKind
                )
            }
        }

        mutating func readRepeatedUInt32Values(
            for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader
        ) throws -> [UInt32] {
            try readRepeatedUInt64Values(for: fieldHeader).map { value in
                guard value <= UInt64(UInt32.max) else {
                    throw OpalFusion.Wire.CashFusionProtobufCodingError
                        .uint32ValueOutOfRange(value)
                }
                return UInt32(value)
            }
        }
}
