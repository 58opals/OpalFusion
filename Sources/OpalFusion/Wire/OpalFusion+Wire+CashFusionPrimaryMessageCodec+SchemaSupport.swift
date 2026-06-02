// OpalFusion+Wire+CashFusionPrimaryMessageCodec+SchemaSupport.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.ServerFailure
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        if let text = message.message {
            try writer.writeStringField(
                text,
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeServerFailure(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ServerFailure {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var message: String?

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                message = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "Error.message"
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(message: message)
    }

    static func decodeEmptyMessage(_ bytes: [UInt8]) throws {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        while let fieldHeader = try reader.readNextFieldHeader() {
            try reader.skipValue(for: fieldHeader)
        }
    }

    static func assignOneOfPayload<Value>(
        _ nextPayload: @autoclosure () throws -> Value,
        to payload: inout Value?,
        messageName: String,
        fieldNumber: Int
    ) throws {
        guard payload == nil else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.conflictingOneOfField(
                messageName: messageName,
                fieldNumber: fieldNumber
            )
        }
        payload = try nextPayload()
    }

    static func requireBytes(
        _ value: [UInt8]?,
        messageName: String,
        fieldNumber: Int
    ) throws -> [UInt8] {
        try requireValue(
            value,
            messageName: messageName,
            fieldNumber: fieldNumber
        )
    }

    static func requireValue<Value>(
        _ value: Value?,
        messageName: String,
        fieldNumber: Int
    ) throws -> Value {
        guard let value else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.missingRequiredField(
                messageName: messageName,
                fieldNumber: fieldNumber
            )
        }
        return value
    }

    static func readStringValue(
        for fieldHeader: OpalFusion.Wire.CashFusionProtobufFieldHeader,
        from reader: inout OpalFusion.Wire.CashFusionProtobufReader,
        fieldName: String
    ) throws -> String {
        do {
            return try reader.readStringValue(for: fieldHeader)
        } catch OpalFusion.Wire.CashFusionProtobufCodingError.invalidUTF8String {
            throw OpalFusion.Wire.PrimaryMessageCodecError.invalidUTF8Field(
                fieldName
            )
        }
    }
}
