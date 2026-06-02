// OpalFusion+Wire+CashFusionPrimaryMessageCodec+TierStatus.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.TierStatusUpdate
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for (tier, status) in message.statusesByTier.sorted(by: { $0.key < $1.key }) {
            try writer.writeBytesField(
                encodeTierStatusMapEntry(
                    tier: tier,
                    status: status
                ),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeTierStatusUpdate(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.TierStatusUpdate {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var statusesByTier: [UInt64: OpalFusion.ProtocolModel.TierStatus] = [:]

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                let entry = try decodeTierStatusMapEntry(
                    try reader.readBytesValue(for: fieldHeader)
                )
                statusesByTier[entry.tier] = entry.status
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(statusesByTier: statusesByTier)
    }

    static func encodeTierStatusMapEntry(
        tier: UInt64,
        status: OpalFusion.ProtocolModel.TierStatus
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt64Field(
            tier,
            fieldNumber: 1
        )
        try writer.writeBytesField(
            encode(status),
            fieldNumber: 2
        )
        return writer.serializedBytes
    }

    static func decodeTierStatusMapEntry(
        _ bytes: [UInt8]
    ) throws -> (tier: UInt64, status: OpalFusion.ProtocolModel.TierStatus) {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tier: UInt64 = 0
        var status = OpalFusion.ProtocolModel.TierStatus(
            playerCount: nil,
            minimumPlayerCount: nil,
            maximumPlayerCount: nil,
            timeRemainingSeconds: nil
        )

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tier = try reader.readUInt64Value(for: fieldHeader)
            case 2:
                status = try decodeTierStatus(try reader.readBytesValue(for: fieldHeader))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return (tier, status)
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.TierStatus
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        if let playerCount = message.playerCount {
            try writer.writeUInt32Field(
                playerCount,
                fieldNumber: 1
            )
        }
        if let minimumPlayerCount = message.minimumPlayerCount {
            try writer.writeUInt32Field(
                minimumPlayerCount,
                fieldNumber: 2
            )
        }
        if let maximumPlayerCount = message.maximumPlayerCount {
            try writer.writeUInt32Field(
                maximumPlayerCount,
                fieldNumber: 3
            )
        }
        if let timeRemainingSeconds = message.timeRemainingSeconds {
            try writer.writeUInt32Field(
                timeRemainingSeconds,
                fieldNumber: 4
            )
        }
        return writer.serializedBytes
    }

    static func decodeTierStatus(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.TierStatus {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var playerCount: UInt32?
        var minimumPlayerCount: UInt32?
        var maximumPlayerCount: UInt32?
        var timeRemainingSeconds: UInt32?

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                playerCount = try reader.readUInt32Value(for: fieldHeader)
            case 2:
                minimumPlayerCount = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                maximumPlayerCount = try reader.readUInt32Value(for: fieldHeader)
            case 4:
                timeRemainingSeconds = try reader.readUInt32Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            playerCount: playerCount,
            minimumPlayerCount: minimumPlayerCount,
            maximumPlayerCount: maximumPlayerCount,
            timeRemainingSeconds: timeRemainingSeconds
        )
    }
}
