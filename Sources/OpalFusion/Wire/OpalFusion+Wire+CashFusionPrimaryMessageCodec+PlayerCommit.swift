// OpalFusion+Wire+CashFusionPrimaryMessageCodec+PlayerCommit.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.PlayerCommit
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for initialCommitment in message.initialCommitments {
            try writer.writeBytesField(
                OpalFusion.Wire.CashFusionInitialCommitmentCodec.encode(
                    initialCommitment
                ),
                fieldNumber: 1
            )
        }
        try writer.writeUInt64Field(
            message.excessFeeSatoshis,
            fieldNumber: 2
        )
        try writer.writeBytesField(
            message.pedersenTotalNonce,
            fieldNumber: 3
        )
        try writer.writeBytesField(
            message.randomNumberCommitment,
            fieldNumber: 4
        )
        for request in message.blindSignatureRequests {
            try writer.writeBytesField(
                request.scalar,
                fieldNumber: 5
            )
        }
        return writer.serializedBytes
    }

    static func decodePlayerCommit(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.PlayerCommit {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var initialCommitments: [OpalFusion.Commitment.InitialCommitment] = []
        var excessFeeSatoshis: UInt64?
        var pedersenTotalNonce: [UInt8]?
        var randomNumberCommitment: [UInt8]?
        var blindSignatureRequests: [OpalFusion.BlindSignature.Request] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                initialCommitments.append(
                    try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode(
                        try reader.readBytesValue(for: fieldHeader)
                    )
                )
            case 2:
                excessFeeSatoshis = try reader.readUInt64Value(for: fieldHeader)
            case 3:
                pedersenTotalNonce = try reader.readBytesValue(for: fieldHeader)
            case 4:
                randomNumberCommitment = try reader.readBytesValue(for: fieldHeader)
            case 5:
                blindSignatureRequests.append(
                    .init(scalar: try reader.readBytesValue(for: fieldHeader))
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            initialCommitments: initialCommitments,
            excessFeeSatoshis: try requireValue(
                excessFeeSatoshis,
                messageName: "PlayerCommit",
                fieldNumber: 2
            ),
            pedersenTotalNonce: try requireBytes(
                pedersenTotalNonce,
                messageName: "PlayerCommit",
                fieldNumber: 3
            ),
            randomNumberCommitment: try requireBytes(
                randomNumberCommitment,
                messageName: "PlayerCommit",
                fieldNumber: 4
            ),
            blindSignatureRequests: blindSignatureRequests
        )
    }
}
