// OpalFusion+Wire+CashFusionCovertMessageCodec+SchemaSupport.swift

extension OpalFusion.Wire.CashFusionCovertMessageCodec {
    static func decodeEmptyMessage(_ bytes: [UInt8]) throws {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        while let fieldHeader = try reader.nextFieldHeader() {
            try reader.skipValue(for: fieldHeader)
        }
    }

    static func assignOneOfPayload<Value>(
        _ nextPayload: Value,
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
        payload = nextPayload
    }
}
