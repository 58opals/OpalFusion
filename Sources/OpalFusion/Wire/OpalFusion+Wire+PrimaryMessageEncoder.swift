// OpalFusion+Wire+PrimaryMessageEncoder.swift

extension OpalFusion.Wire {
    struct PrimaryMessageEncoder: Sendable {
        func encode(_ message: OpalFusion.ProtocolModel.ClientMessage) throws -> [UInt8] {
            do {
                return try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)
            } catch let error as OpalFusion.Wire.PrimaryMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.PrimaryMessageCodecError.protobufDecodingFailed(
                    String(describing: error)
                )
            }
        }

        func encode(_ message: OpalFusion.ProtocolModel.ServerMessage) throws -> [UInt8] {
            do {
                return try OpalFusion.Wire.CashFusionPrimaryMessageCodec.encode(message)
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
