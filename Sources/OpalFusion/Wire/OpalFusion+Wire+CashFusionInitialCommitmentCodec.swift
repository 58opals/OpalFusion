// OpalFusion+Wire+CashFusionInitialCommitmentCodec.swift

extension OpalFusion.Wire {
    enum CashFusionInitialCommitmentCodec {
        static func encode(
            _ commitment: OpalFusion.Commitment.InitialCommitment
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeBytesField(
                commitment.saltedComponentHash,
                fieldNumber: 1
            )
            try writer.writeBytesField(
                commitment.amountCommitment,
                fieldNumber: 2
            )
            try writer.writeBytesField(
                commitment.communicationPublicKey,
                fieldNumber: 3
            )
            return writer.serializedBytes
        }

        static func decode(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.Commitment.InitialCommitment {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var saltedComponentHash: [UInt8]?
            var amountCommitment: [UInt8]?
            var communicationPublicKey: [UInt8]?

            while let fieldHeader = try reader.readNextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    saltedComponentHash = try reader.readBytesValue(for: fieldHeader)
                case 2:
                    amountCommitment = try reader.readBytesValue(for: fieldHeader)
                case 3:
                    communicationPublicKey = try reader.readBytesValue(for: fieldHeader)
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            return try .init(
                saltedComponentHash: requireBytes(
                    saltedComponentHash,
                    fieldNumber: 1
                ),
                amountCommitment: requireBytes(
                    amountCommitment,
                    fieldNumber: 2
                ),
                communicationPublicKey: requireBytes(
                    communicationPublicKey,
                    fieldNumber: 3
                )
            )
        }
    }
}

private extension OpalFusion.Wire.CashFusionInitialCommitmentCodec {
    static func requireBytes(
        _ value: [UInt8]?,
        fieldNumber: Int
    ) throws -> [UInt8] {
        guard let value else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.missingRequiredField(
                messageName: "InitialCommitment",
                fieldNumber: fieldNumber
            )
        }
        return value
    }
}
