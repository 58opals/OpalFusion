// OpalFusion+Wire+CashFusionComponentCodec+Output.swift

extension OpalFusion.Wire.CashFusionComponentCodec {
    static func encodeOutputComponent(
        _ outputComponent: OpalFusion.Commitment.OutputComponent
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            outputComponent.lockingScript,
            fieldNumber: 1
        )
        try writer.writeUInt64Field(
            outputComponent.amountSatoshis,
            fieldNumber: 2
        )
        return writer.serializedBytes
    }

    static func decodeOutputComponent(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Commitment.OutputComponent {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var lockingScript: [UInt8]?
        var amountSatoshis: UInt64?

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                lockingScript = try reader.readBytesValue(for: fieldHeader)
            case 2:
                amountSatoshis = try reader.readUInt64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return try .init(
            lockingScript: requireBytes(
                lockingScript,
                messageName: "OutputComponent",
                fieldNumber: 1
            ),
            amountSatoshis: requireValue(
                amountSatoshis,
                messageName: "OutputComponent",
                fieldNumber: 2
            )
        )
    }

    static func decodeBlankComponent(_ bytes: [UInt8]) throws {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        while let fieldHeader = try reader.readNextFieldHeader() {
            try reader.skipValue(for: fieldHeader)
        }
    }
}
