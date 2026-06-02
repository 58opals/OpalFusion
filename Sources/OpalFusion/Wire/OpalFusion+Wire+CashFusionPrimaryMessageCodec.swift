// OpalFusion+Wire+CashFusionPrimaryMessageCodec.swift

extension OpalFusion.Wire {
    enum CashFusionPrimaryMessageCodec {
        static func encode(
            _ message: OpalFusion.ProtocolModel.ClientMessage
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            switch message {
            case let .clientHello(clientHello):
                try writer.writeBytesField(
                    try encode(clientHello),
                    fieldNumber: 1
                )
            case let .joinPools(joinPools):
                try writer.writeBytesField(
                    encode(joinPools),
                    fieldNumber: 2
                )
            case let .playerCommit(playerCommit):
                try writer.writeBytesField(
                    encode(playerCommit),
                    fieldNumber: 3
                )
            case let .myProofsList(myProofsList):
                try writer.writeBytesField(
                    encode(myProofsList),
                    fieldNumber: 5
                )
            case let .blames(blames):
                try writer.writeBytesField(
                    encode(blames),
                    fieldNumber: 6
                )
            }
            return writer.serializedBytes
        }

        static func encode(
            _ message: OpalFusion.ProtocolModel.ServerMessage
        ) throws -> [UInt8] {
            var writer = OpalFusion.Wire.CashFusionProtobufWriter()
            switch message {
            case let .serverHello(serverHello):
                try writer.writeBytesField(
                    encode(serverHello),
                    fieldNumber: 1
                )
            case let .tierStatusUpdate(update):
                try writer.writeBytesField(
                    encode(update),
                    fieldNumber: 2
                )
            case let .fusionBegin(fusionBegin):
                try writer.writeBytesField(
                    encode(fusionBegin),
                    fieldNumber: 3
                )
            case let .startRound(startRound):
                try writer.writeBytesField(
                    encode(startRound),
                    fieldNumber: 4
                )
            case let .blindSignatureResponses(responses):
                try writer.writeBytesField(
                    encode(responses),
                    fieldNumber: 5
                )
            case let .allCommitments(allCommitments):
                try writer.writeBytesField(
                    encode(allCommitments),
                    fieldNumber: 6
                )
            case let .shareCovertComponents(components):
                try writer.writeBytesField(
                    encode(components),
                    fieldNumber: 7
                )
            case let .fusionResult(result):
                try writer.writeBytesField(
                    encode(result),
                    fieldNumber: 8
                )
            case let .theirProofsList(proofs):
                try writer.writeBytesField(
                    encode(proofs),
                    fieldNumber: 9
                )
            case .restartRound:
                try writer.writeBytesField(
                    [],
                    fieldNumber: 14
                )
            case let .serverFailure(failure):
                try writer.writeBytesField(
                    encode(failure),
                    fieldNumber: 15
                )
            }
            return writer.serializedBytes
        }

        static func decodeClient(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.ProtocolModel.ClientMessage {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var message: OpalFusion.ProtocolModel.ClientMessage?

            while let fieldHeader = try reader.readNextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    try assignOneOfPayload(
                        .clientHello(decodeClientHello(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 1
                    )
                case 2:
                    try assignOneOfPayload(
                        .joinPools(try decodeJoinPools(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 2
                    )
                case 3:
                    try assignOneOfPayload(
                        .playerCommit(try decodePlayerCommit(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 3
                    )
                case 5:
                    try assignOneOfPayload(
                        .myProofsList(try decodeMyProofsList(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 5
                    )
                case 6:
                    try assignOneOfPayload(
                        .blames(try decodeBlames(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ClientMessage",
                        fieldNumber: 6
                    )
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            guard let message else {
                throw OpalFusion.Wire.PrimaryMessageCodecError.missingClientMessageCase
            }
            return message
        }

    }
}
