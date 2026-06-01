// OpalFusion+Wire+CovertMessageDecoder.swift

extension OpalFusion.Wire {
    struct CovertMessageDecoder: Sendable {
        func decodeMessage(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.CovertMessage {
            do {
                return try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeMessage(bytes)
            } catch let error as OpalFusion.Wire.CovertMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed(
                    String(describing: error)
                )
            }
        }

        func decodeResponse(_ bytes: [UInt8]) throws -> OpalFusion.ProtocolModel.CovertResponse {
            do {
                return try OpalFusion.Wire.CashFusionCovertMessageCodec.decodeResponse(bytes)
            } catch let error as OpalFusion.Wire.CovertMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed(
                    String(describing: error)
                )
            }
        }
    }
}
