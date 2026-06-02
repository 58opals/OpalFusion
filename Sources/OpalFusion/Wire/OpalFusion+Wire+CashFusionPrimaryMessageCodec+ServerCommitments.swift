// OpalFusion+Wire+CashFusionPrimaryMessageCodec+ServerCommitments.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.BlindSignatureResponses
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for response in message.responses {
            try writer.writeBytesField(
                response.scalar,
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeBlindSignatureResponses(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.BlindSignatureResponses {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var responses: [OpalFusion.BlindSignature.Response] = []

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                responses.append(.init(scalar: try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(responses: responses)
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.AllCommitments
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for initialCommitment in message.initialCommitments {
            try writer.writeBytesField(
                OpalFusion.Wire.CashFusionInitialCommitmentCodec.encode(
                    initialCommitment
                ),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeAllCommitments(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.AllCommitments {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var initialCommitments: [OpalFusion.Commitment.InitialCommitment] = []

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                initialCommitments.append(
                    try OpalFusion.Wire.CashFusionInitialCommitmentCodec.decode(
                        try reader.readBytesValue(for: fieldHeader)
                    )
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(initialCommitments: initialCommitments)
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.ShareCovertComponents
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for component in message.serializedComponents {
            try writer.writeBytesField(
                component,
                fieldNumber: 4
            )
        }
        if let skipSignatures = message.skipSignatures {
            try writer.writeBoolField(
                skipSignatures,
                fieldNumber: 5
            )
        }
        if let sessionHash = message.sessionHash {
            try writer.writeBytesField(
                sessionHash,
                fieldNumber: 6
            )
        }
        return writer.serializedBytes
    }

    static func decodeShareCovertComponents(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.ShareCovertComponents {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var serializedComponents: [[UInt8]] = []
        var skipSignatures: Bool?
        var sessionHash: [UInt8]?

        while let fieldHeader = try reader.readNextFieldHeader() {
            switch fieldHeader.number {
            case 4:
                serializedComponents.append(try reader.readBytesValue(for: fieldHeader))
            case 5:
                skipSignatures = try reader.readBoolValue(for: fieldHeader)
            case 6:
                sessionHash = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            serializedComponents: serializedComponents,
            skipSignatures: skipSignatures,
            sessionHash: sessionHash
        )
    }
}
