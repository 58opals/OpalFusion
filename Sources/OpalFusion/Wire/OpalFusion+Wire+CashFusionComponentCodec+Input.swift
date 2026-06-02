// OpalFusion+Wire+CashFusionComponentCodec+Input.swift

extension OpalFusion.Wire.CashFusionComponentCodec {
    static func encodeInputComponent(
        _ inputComponent: OpalFusion.Commitment.InputComponent
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            Array(inputComponent.outpointTransactionHash.reversed()),
            fieldNumber: 1
        )
        try writer.writeUInt32Field(
            inputComponent.outpointIndex,
            fieldNumber: 2
        )
        try writer.writeBytesField(
            inputComponent.publicKey,
            fieldNumber: 3
        )
        try writer.writeUInt64Field(
            inputComponent.amountSatoshis,
            fieldNumber: 4
        )
        return writer.serializedBytes
    }

    static func decodeInputComponent(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Commitment.InputComponent {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var previousTransactionID: [UInt8]?
        var previousIndex: UInt32?
        var publicKey: [UInt8]?
        var amountSatoshis: UInt64?

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                previousTransactionID = try reader.readBytesValue(for: fieldHeader)
            case 2:
                previousIndex = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                publicKey = try reader.readBytesValue(for: fieldHeader)
            case 4:
                amountSatoshis = try reader.readUInt64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return try .init(
            outpointTransactionHash: requireBytes(
                previousTransactionID,
                messageName: "InputComponent",
                fieldNumber: 1
            ).reversed(),
            outpointIndex: requireValue(
                previousIndex,
                messageName: "InputComponent",
                fieldNumber: 2
            ),
            publicKey: requireBytes(
                publicKey,
                messageName: "InputComponent",
                fieldNumber: 3
            ),
            amountSatoshis: requireValue(
                amountSatoshis,
                messageName: "InputComponent",
                fieldNumber: 4
            )
        )
    }
}
