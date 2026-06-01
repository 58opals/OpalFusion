// OpalFusion+Wire+CashFusionPrimaryMessageCodec+RoundStart.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.FusionBegin
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt64Field(
            message.tier,
            fieldNumber: 1
        )
        try writer.writeBytesField(
            Array(message.covertDomain.utf8),
            fieldNumber: 2
        )
        try writer.writeUInt32Field(
            message.covertPort,
            fieldNumber: 3
        )
        if let covertSsl = message.covertSsl {
            try writer.writeBoolField(
                covertSsl,
                fieldNumber: 4
            )
        }
        try writer.writeFixed64Field(
            message.serverTimeUnixSeconds,
            fieldNumber: 5
        )
        return writer.serializedBytes
    }

    static func decodeFusionBegin(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.FusionBegin {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var tier: UInt64 = 0
        var covertDomain = ""
        var covertPort: UInt32 = 0
        var covertSsl: Bool?
        var serverTimeUnixSeconds: UInt64 = 0

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                tier = try reader.readUInt64Value(for: fieldHeader)
            case 2:
                covertDomain = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "FusionBegin.covertDomain"
                )
            case 3:
                covertPort = try reader.readUInt32Value(for: fieldHeader)
            case 4:
                covertSsl = try reader.readBoolValue(for: fieldHeader)
            case 5:
                serverTimeUnixSeconds = try reader.readFixed64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            tier: tier,
            covertDomain: covertDomain,
            covertPort: covertPort,
            covertSsl: covertSsl,
            serverTimeUnixSeconds: serverTimeUnixSeconds
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.StartRound
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.roundPublicKey,
            fieldNumber: 1
        )
        for blindNoncePoint in message.blindNoncePoints {
            try writer.writeBytesField(
                blindNoncePoint,
                fieldNumber: 2
            )
        }
        try writer.writeFixed64Field(
            message.serverTimeUnixSeconds,
            fieldNumber: 5
        )
        return writer.serializedBytes
    }

    static func decodeStartRound(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.StartRound {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var roundPublicKey: [UInt8] = []
        var blindNoncePoints: [[UInt8]] = []
        var serverTimeUnixSeconds: UInt64 = 0

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                roundPublicKey = try reader.readBytesValue(for: fieldHeader)
            case 2:
                blindNoncePoints.append(try reader.readBytesValue(for: fieldHeader))
            case 5:
                serverTimeUnixSeconds = try reader.readFixed64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            roundPublicKey: roundPublicKey,
            blindNoncePoints: blindNoncePoints,
            serverTimeUnixSeconds: serverTimeUnixSeconds
        )
    }
}
