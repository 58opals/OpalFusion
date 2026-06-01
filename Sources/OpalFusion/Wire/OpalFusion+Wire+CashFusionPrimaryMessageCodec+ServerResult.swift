// OpalFusion+Wire+CashFusionPrimaryMessageCodec+ServerResult.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
    static func encode(
        _ message: OpalFusion.ProtocolModel.FusionResult
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBoolField(
            message.isSuccess,
            fieldNumber: 1
        )
        for transactionSignature in message.transactionSignatures {
            try writer.writeBytesField(
                transactionSignature,
                fieldNumber: 2
            )
        }
        for badComponentIndex in message.badComponentIndices {
            try writer.writeUInt32Field(
                badComponentIndex,
                fieldNumber: 3
            )
        }
        return writer.serializedBytes
    }

    static func decodeFusionResult(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.FusionResult {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var isSuccess = false
        var transactionSignatures: [[UInt8]] = []
        var badComponentIndices: [UInt32] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                isSuccess = try reader.readBoolValue(for: fieldHeader)
            case 2:
                transactionSignatures.append(try reader.readBytesValue(for: fieldHeader))
            case 3:
                badComponentIndices.append(
                    contentsOf: try reader.readRepeatedUInt32Values(for: fieldHeader)
                )
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            isSuccess: isSuccess,
            transactionSignatures: transactionSignatures,
            badComponentIndices: badComponentIndices
        )
    }

    static func encode(
        _ message: OpalFusion.ProtocolModel.TheirProofsList
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        for proof in message.proofs {
            try writer.writeBytesField(
                encode(proof),
                fieldNumber: 1
            )
        }
        return writer.serializedBytes
    }

    static func decodeTheirProofsList(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.ProtocolModel.TheirProofsList {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var proofs: [OpalFusion.Blame.RelayedProof] = []

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                proofs.append(try decodeRelayedProof(try reader.readBytesValue(for: fieldHeader)))
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(proofs: proofs)
    }

    static func encode(
        _ message: OpalFusion.Blame.RelayedProof
    ) throws -> [UInt8] {
        var writer = OpalFusion.Wire.CashFusionProtobufWriter()
        try writer.writeBytesField(
            message.encryptedProof,
            fieldNumber: 1
        )
        try writer.writeUInt32Field(
            message.sourceCommitmentIndex,
            fieldNumber: 2
        )
        try writer.writeUInt32Field(
            message.destinationKeyIndex,
            fieldNumber: 3
        )
        return writer.serializedBytes
    }

    static func decodeRelayedProof(
        _ bytes: [UInt8]
    ) throws -> OpalFusion.Blame.RelayedProof {
        var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
        var encryptedProof: [UInt8] = []
        var sourceCommitmentIndex: UInt32 = 0
        var destinationKeyIndex: UInt32 = 0

        while let fieldHeader = try reader.nextFieldHeader() {
            switch fieldHeader.number {
            case 1:
                encryptedProof = try reader.readBytesValue(for: fieldHeader)
            case 2:
                sourceCommitmentIndex = try reader.readUInt32Value(for: fieldHeader)
            case 3:
                destinationKeyIndex = try reader.readUInt32Value(for: fieldHeader)
            default:
                try reader.skipValue(for: fieldHeader)
            }
        }

        return .init(
            encryptedProof: encryptedProof,
            sourceCommitmentIndex: sourceCommitmentIndex,
            destinationKeyIndex: destinationKeyIndex
        )
    }
}
