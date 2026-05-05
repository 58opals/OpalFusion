// OpalFusion+Wire+PrimaryFrame.swift

extension OpalFusion.Wire {
    enum PrimaryFrameError: Swift.Error, Equatable {
        case invalidMagic([UInt8])
        case invalidLength(Int)
        case payloadTooLarge(Int)
    }

    struct PrimaryFrameEncoder: Sendable {
        let configuration: OpalFusion.Transport.FrameConfiguration

        init(configuration: OpalFusion.Transport.FrameConfiguration) {
            self.configuration = configuration
        }

        func encode(payload: [UInt8]) throws -> [UInt8] {
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

    struct PrimaryFrameDecoder: Sendable {
        let configuration: OpalFusion.Transport.FrameConfiguration
        private(set) var bufferedBytes: [UInt8]

        init(
            configuration: OpalFusion.Transport.FrameConfiguration,
            bufferedBytes: [UInt8] = []
        ) {
            self.configuration = configuration
            self.bufferedBytes = bufferedBytes
        }

        mutating func append(_ incomingBytes: [UInt8]) throws -> [[UInt8]] {
            bufferedBytes.append(contentsOf: incomingBytes)

            var payloads: [[UInt8]] = []
            let headerLength = configuration.magicBytes.count + 4

            while bufferedBytes.count >= headerLength {
                let magic = Array(bufferedBytes.prefix(configuration.magicBytes.count))
                guard magic == configuration.magicBytes else {
                    if payloads.isEmpty == false {
                        return payloads
                    }
                    throw OpalFusion.Wire.PrimaryFrameError.invalidMagic(magic)
                }

                let payloadLength = Self.parseLength(
                    from: bufferedBytes[configuration.magicBytes.count..<headerLength]
                )
                guard payloadLength > 0 else {
                    if payloads.isEmpty == false {
                        return payloads
                    }
                    throw OpalFusion.Wire.PrimaryFrameError.invalidLength(payloadLength)
                }
                guard payloadLength <= configuration.maximumMessageLengthBytes else {
                    if payloads.isEmpty == false {
                        return payloads
                    }
                    throw OpalFusion.Wire.PrimaryFrameError.payloadTooLarge(payloadLength)
                }

                let frameLength = headerLength + payloadLength
                guard bufferedBytes.count >= frameLength else {
                    break
                }

                payloads.append(Array(bufferedBytes[headerLength..<frameLength]))
                bufferedBytes.removeFirst(frameLength)
            }

            return payloads
        }

        private static func parseLength(
            from bytes: ArraySlice<UInt8>
        ) -> Int {
            bytes.reduce(0) { partialResult, byte in
                (partialResult << 8) | Int(byte)
            }
        }
    }
}
