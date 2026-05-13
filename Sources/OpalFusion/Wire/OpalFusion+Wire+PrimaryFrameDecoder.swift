// OpalFusion+Wire+PrimaryFrameDecoder.swift

extension OpalFusion.Wire {
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
            guard configuration.magicBytes.isEmpty == false else {
                throw OpalFusion.Wire.PrimaryFrameError.invalidMagic([])
            }
            bufferedBytes.append(contentsOf: incomingBytes)

            var payloads: [[UInt8]] = []
            let headerLength = configuration.magicBytes.count + 4

            while bufferedBytes.count >= headerLength {
                let magic = Array(bufferedBytes.prefix(configuration.magicBytes.count))
                guard magic == configuration.magicBytes else {
                    return try finishOrThrow(
                        payloads,
                        error: .invalidMagic(magic)
                    )
                }

                let payloadLength = Self.parseLength(
                    from: bufferedBytes[configuration.magicBytes.count..<headerLength]
                )
                guard payloadLength > 0 else {
                    return try finishOrThrow(
                        payloads,
                        error: .invalidLength(payloadLength)
                    )
                }
                guard payloadLength <= configuration.maximumMessageLengthBytes else {
                    return try finishOrThrow(
                        payloads,
                        error: .payloadTooLarge(payloadLength)
                    )
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

        private func finishOrThrow(
            _ payloads: [[UInt8]],
            error: OpalFusion.Wire.PrimaryFrameError
        ) throws -> [[UInt8]] {
            guard payloads.isEmpty else {
                return payloads
            }

            throw error
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
