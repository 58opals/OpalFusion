// OpalFusion+Wire+PrimaryMessageDecoder.swift

extension OpalFusion.Wire {
    struct PrimaryMessageDecoder: Sendable {
        func decodeClient(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.ClientMessage {
            do {
                return try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeClient(bytes)
            } catch let error as OpalFusion.Wire.PrimaryMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed(
                    String(describing: error)
                )
            }
        }

        func decodeServer(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.ServerMessage {
            do {
                return try OpalFusion.Wire.CashFusionPrimaryMessageCodec.decodeServer(bytes)
            } catch let error as OpalFusion.Wire.PrimaryMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed(
                    String(describing: error)
                )
            }
        }
    }
}
