// OpalFusion+Wire+CashFusionPrimaryMessageCodec+ClientBlame.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.MyProofsList
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for encryptedProof in message.encryptedProofs {
            try writer.writeBytesField(
                encryptedProof,
                fieldNumber: 1
            )
        }
        try writer.writeBytesField(
            message.randomNumber,
            fieldNumber: 2
        )
        return writer.serializedBytes
    }

    static func decodeMyProofsList(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.MyProofsList {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var encryptedProofs: [[UInt8]] = []
        var randomNumber: [UInt8] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                encryptedProofs.append(try reader.readBytesValue(for: fieldHeader))
            case 2:
                randomNumber = try reader.readBytesValue(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            encryptedProofs: encryptedProofs,
            randomNumber: randomNumber
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.Blames
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for blame in message.blames {
            try writer.writeBytesField(
                encode(blame),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeBlames(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.Blames {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var blames: [OpalFusion.Blame.BlameProof] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                blames.append(try decodeBlameProof(try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(blames: blames)
    }

    static func encode(
        _ message: OpalFusion.Blame.BlameProof
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeUInt32Field(
            message.proofIndex,
            fieldNumber: 1
        )
        switch message.decrypter {
        case let .sessionKey(sessionKey):
            try writer.writeBytesField(
                sessionKey,
                fieldNumber: 2
            )
        case let .privateKey(privateKey):
            try writer.writeBytesField(
                privateKey,
                fieldNumber: 3
            )
        }
        if let requiresLookup = message.requiresBlockchainLookup {
            try writer.writeBoolField(
                requiresLookup,
                fieldNumber: 4
            )
        }
        if let reason = message.reason {
            try writer.writeStringField(
                reason,
                fieldNumber: 5
            )
        }
        return writer.serializedBytes
    }

    static func decodeBlameProof(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Blame.BlameProof {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var proofIndex: UInt32 = 0
        var decrypter: OpalFusion.Blame.Decrypter?
        var requiresBlockchainLookup: Bool?
        var reason: String?

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                proofIndex = try reader.readUInt32Value(for: fieldHeader)
            case 2:
                try assignOneOfPayload(
                    .sessionKey(try reader.readBytesValue(for: fieldHeader)),
                    to: &decrypter,
                    messageName: "BlameProof",
                    fieldNumber: 2
                )
            case 3:
                try assignOneOfPayload(
                    .privateKey(try reader.readBytesValue(for: fieldHeader)),
                    to: &decrypter,
                    messageName: "BlameProof",
                    fieldNumber: 3
                )
            case 4:
                requiresBlockchainLookup = try reader.readBoolValue(for: fieldHeader)
            case 5:
                reason = try readStringValue(
                    for: fieldHeader,
                    from: &reader,
                    fieldName: "BlameProof.blameReason"
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        guard let decrypter else {
            throw OpalFusion.Wire.PrimaryMessageCodecError.missingBlameDecrypter
        }

        return .init(
            proofIndex: proofIndex,
            decrypter: decrypter,
            requiresBlockchainLookup: requiresBlockchainLookup,
            reason: reason
        )
    }
}
