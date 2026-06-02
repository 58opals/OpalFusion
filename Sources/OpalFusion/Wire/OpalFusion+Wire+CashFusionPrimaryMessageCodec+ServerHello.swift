// OpalFusion+Wire+CashFusionPrimaryMessageCodec+ServerHello.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.ServerHello
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for tier in message.tiers {
            try writer.writeUInt64Field(
                tier,
                fieldNumber: 1
            )
        }
        try writer.writeUInt32Field(
            message.numberOfComponents,
            fieldNumber: 2
        )
        try writer.writeUInt64Field(
            message.componentFeeRateSatoshisPerKb,
            fieldNumber: 4
        )
        try writer.writeUInt64Field(
            message.minimumExcessFeeSatoshis,
            fieldNumber: 5
        )
        try writer.writeUInt64Field(
            message.maximumExcessFeeSatoshis,
            fieldNumber: 6
        )
        if let donationAddress = message.donationAddress {
            try writer.writeStringField(
                donationAddress,
                fieldNumber: 15
            )
        }
        return writer.serializedBytes
    }

    static func decodeServerHello(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ServerHello {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tiers: [UInt64] = []
        var numberOfComponents: UInt32?
        var componentFeeRateSatoshisPerKb: UInt64?
        var minimumExcessFeeSatoshis: UInt64?
        var maximumExcessFeeSatoshis: UInt64?
        var donationAddress: String?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tiers.append(contentsOf: try reader.readRepeatedUInt64Values(for: fieldHeader))
            case 2:
                numberOfComponents = try reader.readUInt32Value(for: fieldHeader)
            case 4:
                componentFeeRateSatoshisPerKb = try reader.readUInt64Value(for: fieldHeader)
            case 5:
                minimumExcessFeeSatoshis = try reader.readUInt64Value(for: fieldHeader)
            case 6:
                maximumExcessFeeSatoshis = try reader.readUInt64Value(for: fieldHeader)
            case 15:
                donationAddress = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "ServerHello.donationAddress"
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            tiers: tiers,
            numberOfComponents: try requireValue(
                numberOfComponents,
                messageName: "ServerHello",
                fieldNumber: 2
            ),
            componentFeeRateSatoshisPerKb: try requireValue(
                componentFeeRateSatoshisPerKb,
                messageName: "ServerHello",
                fieldNumber: 4
            ),
            minimumExcessFeeSatoshis: try requireValue(
                minimumExcessFeeSatoshis,
                messageName: "ServerHello",
                fieldNumber: 5
            ),
            maximumExcessFeeSatoshis: try requireValue(
                maximumExcessFeeSatoshis,
                messageName: "ServerHello",
                fieldNumber: 6
            ),
            donationAddress: donationAddress
        )
    }
}
