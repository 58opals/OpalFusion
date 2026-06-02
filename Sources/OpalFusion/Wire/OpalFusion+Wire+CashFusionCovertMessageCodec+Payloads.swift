// OpalFusion+Wire+CashFusionCovertMessageCodec+Payloads.swift

extension OpalFusion.Wire.CashFusionCovertMessageCodec {
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
        var signature: [UInt8]?
        var serializedComponent: [UInt8]?

        while let fieldHeader = try reader.readNextFieldHeader() {
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
            signature: try requireBytes(
                signature,
                messageName: "CovertComponent",
                fieldNumber: 2
            ),
            serializedComponent: try requireBytes(
                serializedComponent,
                messageName: "CovertComponent",
                fieldNumber: 3
            )
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
        var inputIndex: UInt32?
        var transactionSignature: [UInt8]?

        while let fieldHeader = try reader.readNextFieldHeader() {
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
            inputIndex: try requireValue(
                inputIndex,
                messageName: "CovertTransactionSignature",
                fieldNumber: 2
            ),
            transactionSignature: try requireBytes(
                transactionSignature,
                messageName: "CovertTransactionSignature",
                fieldNumber: 3
            )
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

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                message = try reader.readStringValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(message: message)
    }
}
