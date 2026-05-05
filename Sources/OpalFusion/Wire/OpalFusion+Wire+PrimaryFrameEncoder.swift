// OpalFusion+Wire+PrimaryFrameEncoder.swift

extension OpalFusion.Wire {
    struct PrimaryFrameEncoder: Sendable {
        let configuration: OpalFusion.Transport.FrameConfiguration

        init(configuration: OpalFusion.Transport.FrameConfiguration) {
            self.configuration = configuration
        }

        func encode(payload: [UInt8]) throws -> [UInt8] {
            guard configuration.magicBytes.isEmpty == false else {
                throw OpalFusion.Wire.PrimaryFrameError.invalidMagic([])
            }
            guard payload.isEmpty == false else {
                throw OpalFusion.Wire.PrimaryFrameError.invalidLength(0)
            }
            guard payload.count <= configuration.maximumMessageLengthBytes else {
                throw OpalFusion.Wire.PrimaryFrameError.payloadTooLarge(payload.count)
            }

            var framed = configuration.magicBytes
            framed.reserveCapacity(configuration.magicBytes.count + 4 + payload.count)
            framed.append(contentsOf: Self.lengthPrefix(for: payload.count))
            framed.append(contentsOf: payload)
            return framed
        }

        private static func lengthPrefix(for payloadCount: Int) -> [UInt8] {
            let length = UInt32(payloadCount)
            return [
                UInt8((length >> 24) & 0xFF),
                UInt8((length >> 16) & 0xFF),
                UInt8((length >> 8) & 0xFF),
                UInt8(length & 0xFF)
            ]
        }
    }
}
