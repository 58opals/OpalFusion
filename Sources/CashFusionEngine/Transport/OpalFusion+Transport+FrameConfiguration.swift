import OpalFusionCore

// OpalFusion+Transport+FrameConfiguration.swift

public extension OpalFusion.Transport {
    /// Framing values shared by the primary and covert CashFusion message channels.
    struct FrameConfiguration: Sendable, Equatable {
        /// Electron Cash frame magic from `connection.py`.
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
