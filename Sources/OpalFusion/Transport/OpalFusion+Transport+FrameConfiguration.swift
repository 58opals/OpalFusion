// OpalFusion+Transport+FrameConfiguration.swift

public extension OpalFusion.Transport {
    /// Framing values for the primary CashFusion message channel.
    struct FrameConfiguration: Sendable, Equatable {
        /// Electron Cash primary-channel frame magic from `connection.py`.
        public let magicBytes: [UInt8]
        /// Electron Cash maximum framed message length from `connection.py`.
        public let maximumMessageLengthBytes: Int

        public init(
            magicBytes: [UInt8],
            maximumMessageLengthBytes: Int
        ) {
            self.magicBytes = magicBytes
            self.maximumMessageLengthBytes = maximumMessageLengthBytes
        }
    }
}
