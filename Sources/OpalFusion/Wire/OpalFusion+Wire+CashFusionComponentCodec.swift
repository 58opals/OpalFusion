// OpalFusion+Wire+CashFusionComponentCodec.swift

extension OpalFusion.Wire {
    enum CashFusionComponentCodec {
        static func encode(
            payload: OpalFusion.Commitment.ComponentPayload,
            saltCommitment: [UInt8]
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            try writer.writeBytesField(
                saltCommitment,
                fieldNumber: 1
            )

            switch payload {
            case let .input(inputComponent):
                try writer.writeBytesField(
                    encodeInputComponent(inputComponent),
                    fieldNumber: 2
                )
            case let .output(outputComponent):
                try writer.writeBytesField(
                    encodeOutputComponent(outputComponent),
                    fieldNumber: 3
                )
            case .blank:
                try writer.writeBytesField(
                    [],
                    fieldNumber: 4
                )
            }

            return writer.serializedBytes
        }

        static func decode(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.Wire.CashFusionComponentData {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var saltCommitment: [UInt8]?
            var payload: OpalFusion.Commitment.ComponentPayload?

            while let fieldHeader = try reader.nextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    saltCommitment = try reader.readBytesValue(for: fieldHeader)
                case 2:
                    try assignOneOfPayload(
                        .input(decodeInputComponent(try reader.readBytesValue(for: fieldHeader))),
                        to: &payload,
                        fieldNumber: 2
                    )
                case 3:
                    try assignOneOfPayload(
                        .output(decodeOutputComponent(try reader.readBytesValue(for: fieldHeader))),
                        to: &payload,
                        fieldNumber: 3
                    )
                case 4:
                    try decodeBlankComponent(try reader.readBytesValue(for: fieldHeader))
                    try assignOneOfPayload(
                        .blank(.init()),
                        to: &payload,
                        fieldNumber: 4
                    )
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            return try .init(
                saltCommitment: requireBytes(
                    saltCommitment,
                    messageName: "Component",
                    fieldNumber: 1
                ),
                payload: payload
            )
        }
    }
}
