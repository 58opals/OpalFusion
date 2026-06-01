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
                saltCommitment: requiredBytes(
                    saltCommitment,
                    messageName: "Component",
                    fieldNumber: 1
                ),
                payload: payload
            )
        }
    }
}

private extension OpalFusion.Wire.CashFusionComponentCodec {
    static func encodeInputComponent(
        _ inputComponent: OpalFusion.Commitment.InputComponent
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            Array(inputComponent.outpointTransactionHash.reversed()),
            fieldNumber: 1
        )
        try writer.writeUInt32Field(
            inputComponent.outpointIndex,
            fieldNumber: 2
        )
        try writer.writeBytesField(
            inputComponent.publicKey,
            fieldNumber: 3
        )
        try writer.writeUInt64Field(
            inputComponent.amountSatoshis,
            fieldNumber: 4
        )
        return writer.serializedBytes
    }

    static func decodeInputComponent(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Commitment.InputComponent {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var previousTransactionID: [UInt8]?
        var previousIndex: UInt32?
        var publicKey: [UInt8]?
        var amountSatoshis: UInt64?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                previousTransactionID = try reader.readBytesValue(for: fieldHeader)
            case 2:
                previousIndex = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                publicKey = try reader.readBytesValue(for: fieldHeader)
            case 4:
                amountSatoshis = try reader.readUInt64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return try .init(
            outpointTransactionHash: requiredBytes(
                previousTransactionID,
                messageName: "InputComponent",
                fieldNumber: 1
            ).reversed(),
            outpointIndex: requiredValue(
                previousIndex,
                messageName: "InputComponent",
                fieldNumber: 2
            ),
            publicKey: requiredBytes(
                publicKey,
                messageName: "InputComponent",
                fieldNumber: 3
            ),
            amountSatoshis: requiredValue(
                amountSatoshis,
                messageName: "InputComponent",
                fieldNumber: 4
            )
        )
    }

    static func encodeOutputComponent(
        _ outputComponent: OpalFusion.Commitment.OutputComponent
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            outputComponent.lockingScript,
            fieldNumber: 1
        )
        try writer.writeUInt64Field(
            outputComponent.amountSatoshis,
            fieldNumber: 2
        )
        return writer.serializedBytes
    }

    static func decodeOutputComponent(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Commitment.OutputComponent {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var lockingScript: [UInt8]?
        var amountSatoshis: UInt64?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                lockingScript = try reader.readBytesValue(for: fieldHeader)
            case 2:
                amountSatoshis = try reader.readUInt64Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return try .init(
            lockingScript: requiredBytes(
                lockingScript,
                messageName: "OutputComponent",
                fieldNumber: 1
            ),
            amountSatoshis: requiredValue(
                amountSatoshis,
                messageName: "OutputComponent",
                fieldNumber: 2
            )
        )
    }

    static func decodeBlankComponent(_ bytes: [UInt8]) throws {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        while let fieldHeader = try reader.nextFieldHeader() {
            try reader.skipValue(for: fieldHeader)
        }
    }

    static func assignOneOfPayload(
        _ nextPayload: OpalFusion.Commitment.ComponentPayload,
        to payload: inout OpalFusion.Commitment.ComponentPayload?,
        fieldNumber: Int
    ) throws {
        guard payload == nil else {
            throw OpalFusion.Wire.CashFusionProtobufCodingError.conflictingOneOfField(
                messageName: "Component",
                fieldNumber: fieldNumber
            )
        }
        payload = nextPayload
    }

    static func requiredBytes(
        _ value: [UInt8]?,
        messageName: String,
        fieldNumber: Int
    ) throws -> [UInt8] {
        try requiredValue(
            value,
            messageName: messageName,
            fieldNumber: fieldNumber
        )
    }

    static func requiredValue<Value>(
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
