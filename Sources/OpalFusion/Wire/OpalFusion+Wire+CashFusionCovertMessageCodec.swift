// OpalFusion+Wire+CashFusionCovertMessageCodec.swift

extension OpalFusion.Wire {
    enum CashFusionCovertMessageCodec {
        static func encode(
            _ message: OpalFusion.ProtocolModel.CovertMessage
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            switch message {
            case let .component(component):
                try writer.writeBytesField(
                    encode(component),
                    fieldNumber: 1
                )
            case let .transactionSignature(signature):
                try writer.writeBytesField(
                    encode(signature),
                    fieldNumber: 2
                )
            case .ping:
                try writer.writeBytesField(
                    [],
                    fieldNumber: 3
                )
            }
            return writer.serializedBytes
        }

        static func encode(
            _ response: OpalFusion.ProtocolModel.CovertResponse
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            switch response {
            case .acknowledgement:
                try writer.writeBytesField(
                    [],
                    fieldNumber: 1
                )
            case let .serverFailure(failure):
                try writer.writeBytesField(
                    encode(failure),
                    fieldNumber: 15
                )
            }
            return writer.serializedBytes
        }

        static func decodeMessage(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.ProtocolModel.CovertMessage {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var message: OpalFusion.ProtocolModel.CovertMessage?

            while let fieldHeader = try reader.nextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    try assignOneOfPayload(
                        .component(try decodeCovertComponent(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "CovertMessage",
                        fieldNumber: 1
                    )
                case 2:
                    try assignOneOfPayload(
                        .transactionSignature(try decodeCovertTransactionSignature(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "CovertMessage",
                        fieldNumber: 2
                    )
                case 3:
                    try decodeEmptyMessage(try reader.readBytesValue(for: fieldHeader))
                    try assignOneOfPayload(
                        .ping(.init()),
                        to: &message,
                        messageName: "CovertMessage",
                        fieldNumber: 3
                    )
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            guard let message else {
                throw OpalFusion.Wire.CovertMessageCodecError.missingCovertMessageCase
            }
            return message
        }

        static func decodeResponse(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.ProtocolModel.CovertResponse {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var response: OpalFusion.ProtocolModel.CovertResponse?

            while let fieldHeader = try reader.nextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    try decodeEmptyMessage(try reader.readBytesValue(for: fieldHeader))
                    try assignOneOfPayload(
                        .acknowledgement(.init()),
                        to: &response,
                        messageName: "CovertResponse",
                        fieldNumber: 1
                    )
                case 15:
                    try assignOneOfPayload(
                        .serverFailure(try decodeServerFailure(try reader.readBytesValue(for: fieldHeader))),
                        to: &response,
                        messageName: "CovertResponse",
                        fieldNumber: 15
                    )
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            guard let response else {
                throw OpalFusion.Wire.CovertMessageCodecError.missingCovertResponseCase
            }
            return response
        }
    }
}

private extension OpalFusion.Wire.CashFusionCovertMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.CovertComponent
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        if let roundPublicKey = message.roundPublicKey {
            try writer.writeBytesField(
                roundPublicKey,
                fieldNumber: 1
            )
        }
        try writer.writeBytesField(
            message.signature,
            fieldNumber: 2
        )
        try writer.writeBytesField(
            message.serializedComponent,
            fieldNumber: 3
        )
        return writer.serializedBytes
    }

    static func decodeCovertComponent(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.CovertComponent {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var roundPublicKey: [UInt8]?
        var signature: [UInt8] = []
        var serializedComponent: [UInt8] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                roundPublicKey = try reader.readBytesValue(for: fieldHeader)
            case 2:
                signature = try reader.readBytesValue(for: fieldHeader)
            case 3:
                serializedComponent = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            roundPublicKey: roundPublicKey,
            signature: signature,
            serializedComponent: serializedComponent
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.CovertTransactionSignature
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        if let roundPublicKey = message.roundPublicKey {
            try writer.writeBytesField(
                roundPublicKey,
                fieldNumber: 1
            )
        }
        try writer.writeUInt32Field(
            message.inputIndex,
            fieldNumber: 2
        )
        try writer.writeBytesField(
            message.transactionSignature,
            fieldNumber: 3
        )
        return writer.serializedBytes
    }

    static func decodeCovertTransactionSignature(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.CovertTransactionSignature {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var roundPublicKey: [UInt8]?
        var inputIndex: UInt32 = 0
        var transactionSignature: [UInt8] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                roundPublicKey = try reader.readBytesValue(for: fieldHeader)
            case 2:
                inputIndex = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                transactionSignature = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            roundPublicKey: roundPublicKey,
            inputIndex: inputIndex,
            transactionSignature: transactionSignature
        )
    }

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

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                message = try reader.readStringValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(message: message)
    }

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
