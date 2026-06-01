// OpalFusion+Wire+CashFusionPrimaryMessageCodec+ClientHello.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.ClientHello
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.versionBytes,
            fieldNumber: 1
        )
        if let genesisHash = message.genesisHash {
            try writer.writeBytesField(
                genesisHash,
                fieldNumber: 2
            )
        }
        return writer.serializedBytes
    }

    static func decodeClientHello(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ClientHello {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var versionBytes: [UInt8] = []
        var genesisHash: [UInt8]?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                versionBytes = try reader.readBytesValue(for: fieldHeader)
            case 2:
                genesisHash = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            versionBytes: versionBytes,
            genesisHash: genesisHash
        )
    }
}
