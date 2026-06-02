// OpalFusion+Wire+CashFusionPrimaryMessageCodec+ServerEnvelope.swift

extension OpalFusion.Wire.CashFusionPrimaryMessageCodec {
        static func decodeServer(
            _ bytes: [UInt8]
        ) throws -> OpalFusion.ProtocolModel.ServerMessage {
            var reader = OpalFusion.Wire.CashFusionProtobufReader(bytes: bytes)
            var message: OpalFusion.ProtocolModel.ServerMessage?

            while let fieldHeader = try reader.readNextFieldHeader() {
                switch fieldHeader.number {
                case 1:
                    try assignOneOfPayload(
                        .serverHello(try decodeServerHello(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 1
                    )
                case 2:
                    try assignOneOfPayload(
                        .tierStatusUpdate(try decodeTierStatusUpdate(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 2
                    )
                case 3:
                    try assignOneOfPayload(
                        .fusionBegin(try decodeFusionBegin(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 3
                    )
                case 4:
                    try assignOneOfPayload(
                        .startRound(try decodeStartRound(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 4
                    )
                case 5:
                    try assignOneOfPayload(
                        .blindSignatureResponses(try decodeBlindSignatureResponses(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 5
                    )
                case 6:
                    try assignOneOfPayload(
                        .allCommitments(try decodeAllCommitments(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 6
                    )
                case 7:
                    try assignOneOfPayload(
                        .shareCovertComponents(try decodeShareCovertComponents(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 7
                    )
                case 8:
                    try assignOneOfPayload(
                        .fusionResult(try decodeFusionResult(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 8
                    )
                case 9:
                    try assignOneOfPayload(
                        .theirProofsList(try decodeTheirProofsList(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 9
                    )
                case 14:
                    try decodeEmptyMessage(try reader.readBytesValue(for: fieldHeader))
                    try assignOneOfPayload(
                        .restartRound(.init()),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 14
                    )
                case 15:
                    try assignOneOfPayload(
                        .serverFailure(try decodeServerFailure(try reader.readBytesValue(for: fieldHeader))),
                        to: &message,
                        messageName: "ServerMessage",
                        fieldNumber: 15
                    )
                default:
                    try reader.skipValue(for: fieldHeader)
                }
            }

            guard let message else {
                throw OpalFusion.Wire.PrimaryMessageCodecError.missingServerMessageCase
            }
            return message
        }
}
