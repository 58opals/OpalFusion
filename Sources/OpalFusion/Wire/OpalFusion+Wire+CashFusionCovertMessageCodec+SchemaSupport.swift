// OpalFusion+Wire+CashFusionCovertMessageCodec+SchemaSupport.swift

extension OpalFusion.Wire.CashFusionCovertMessageCodec {
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
}
