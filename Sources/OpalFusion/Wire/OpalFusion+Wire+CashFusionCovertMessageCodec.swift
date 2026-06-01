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
