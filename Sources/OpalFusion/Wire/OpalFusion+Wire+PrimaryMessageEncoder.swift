// OpalFusion+Wire+PrimaryMessageEncoder.swift

extension OpalFusion.Wire {
    struct PrimaryMessageEncoder: Sendable {
        func encode(_ message: OpalFusion.ProtocolModel.ClientMessage) throws -> [UInt8] {
            try Self.encodeMessage {
                try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)
            }
        }

        func encode(_ message: OpalFusion.ProtocolModel.ServerMessage) throws -> [UInt8] {
            try Self.encodeMessage {
                try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)
            }
        }
    }
}

private extension OpalFusion.Wire.PrimaryMessageEncoder {
    static func encodeMessage(
        _ operation: () throws -> [UInt8]
    ) throws -> [UInt8] {
        do {
            return try operation()
        } catch let error as OpalFusion.Wire.PrimaryMessageCodecError {
            throw error
        } catch {
            throw OpalFusion.Wire.PrimaryMessageCodecError.protobufCodingFailed(
                String(describing: error)
            )
        }
    }
}
