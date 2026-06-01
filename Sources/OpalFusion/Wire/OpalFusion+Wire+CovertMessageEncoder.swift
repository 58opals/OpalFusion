// OpalFusion+Wire+CovertMessageEncoder.swift

extension OpalFusion.Wire {
    struct CovertMessageEncoder: Sendable {
        func encode(_ message: OpalFusion.ProtocolModel.CovertMessage) throws -> [UInt8] {
            do {
                return try OpalFusion.Wire.CashFusionCovertMessageCodec.encode(message)
            } catch let error as OpalFusion.Wire.CovertMessageCodecError {
                throw error
            } catch {
                throw OpalFusion.Wire.CovertMessageCodecError.protobufCodingFailed(
                    String(describing: error)
                )
            }
        }

        func encode(_ response: OpalFusion.ProtocolModel.CovertResponse) throws -> [UInt8] {
            do {
                return try OpalFusion.Wire.CashFusionCovertMessageCodec.encode(response)
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
