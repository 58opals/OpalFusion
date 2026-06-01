// OpalFusion+Wire+CashFusionProofCodec.swift

extension OpalFusion.Wire {
    enum CashFusionProofCodec {
        static func encode(
            _ proof: OpalFusion.Blame.Proof
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeFixed32Field(
                proof.componentIndex,
                fieldNumber: 1
            )
            try writer.writeBytesField(
                proof.salt,
                fieldNumber: 2
            )
            try writer.writeBytesField(
                proof.pedersenNonce,
                fieldNumber: 3
            )
            return writer.serializedBytes
        }

        static func decode(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.Blame.Proof {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var componentIndex: UInt32?
            var salt: [UInt8]?
            var pedersenNonce: [UInt8]?

            while let fieldHeader = try reader.nextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    componentIndex = try reader.readFixed32Value(for: fieldHeader)
                case 2:
                    salt = try reader.readBytesValue(for: fieldHeader)
                case 3:
                    pedersenNonce = try reader.readBytesValue(for: fieldHeader)
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            return try .init(
                componentIndex: requiredValue(
                    componentIndex,
                    fieldNumber: 1
                ),
                salt: requiredValue(
                    salt,
                    fieldNumber: 2
                ),
                pedersenNonce: requiredValue(
                    pedersenNonce,
                    fieldNumber: 3
                )
            )
        }
    }
}

private extension OpalFusion.Wire.CashFusionProofCodec {
    static func requiredValue<Value>(
        _ value: Value?,
        fieldNumber: Int
    ) throws -> Value {
        guard let value else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.missingRequiredField(
                messageName: "Proof",
                fieldNumber: fieldNumber
            )
        }
        return value
    }
}
