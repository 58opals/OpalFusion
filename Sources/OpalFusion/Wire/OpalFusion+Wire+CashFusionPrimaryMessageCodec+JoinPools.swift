// OpalFusion+Wire+CashFusionPrimaryMessageCodec+JoinPools.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.JoinPools
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for tier in message.tiers {
            try writer.writeUInt64Field(
                tier,
                fieldNumber: 1
            )
        }
        for tag in message.tags {
            try writer.writeBytesField(
                encode(tag),
                fieldNumber: 2
            )
        }
        return writer.serializedBytes
    }

    static func decodeJoinPools(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.JoinPools {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tiers: [UInt64] = []
        var tags: [OpalFusion.ProtocolModel.PoolTag] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tiers.append(contentsOf: try reader.readRepeatedUInt64Values(for: fieldHeader))
            case 2:
                tags.append(try decodePoolTag(try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            tiers: tiers,
            tags: tags
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.PoolTag
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.identifier,
            fieldNumber: 1
        )
        try writer.writeUInt32Field(
            message.limit,
            fieldNumber: 2
        )
        if let noIp = message.noIp {
            try writer.writeBoolField(
                noIp,
                fieldNumber: 3
            )
        }
        return writer.serializedBytes
    }

    static func decodePoolTag(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.PoolTag {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var identifier: [UInt8] = []
        var limit: UInt32 = 0
        var noIp: Bool?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                identifier = try reader.readBytesValue(for: fieldHeader)
            case 2:
                limit = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                noIp = try reader.readBoolValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            identifier: identifier,
            limit: limit,
            noIp: noIp
        )
    }
}
