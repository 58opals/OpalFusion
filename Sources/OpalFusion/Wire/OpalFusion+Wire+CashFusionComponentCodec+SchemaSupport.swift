// OpalFusion+Wire+CashFusionComponentCodec+SchemaSupport.swift

extension OpalFusion.Wire.CashFusionComponentCodec {
    static func assignOneOfPayload(
        _ nextPayload: @autoclosure () throws -> OpalFusion.Commitment.ComponentPayload,
        to payload: inout OpalFusion.Commitment.ComponentPayload?,
        fieldNumber: Int
    ) throws {
        guard payload == nil else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.conflictingOneOfField(
                messageName: "Component",
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
