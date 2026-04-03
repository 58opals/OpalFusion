// OpalFusion+Transport+ProtocolIdentityConfiguration.swift

public extension OpalFusion.Transport {
    /// Pinned protocol identity values shared uniformly across interoperable participants.
    struct ProtocolIdentityConfiguration: Sendable, Equatable {
        /// Electron Cash `Protocol.VERSION`.
        public let versionBytes: [UInt8]
        /// Electron Cash `Protocol.FUSE_ID`.
        public let fusionLokadId: [UInt8]
        /// Electron Cash `Protocol.MIN_OUTPUT`.
        public let minimumOutputAmountSatoshis: UInt64

        public init(
            versionBytes: [UInt8],
            fusionLokadId: [UInt8],
            minimumOutputAmountSatoshis: UInt64
        ) {
            self.versionBytes = versionBytes
            self.fusionLokadId = fusionLokadId
            self.minimumOutputAmountSatoshis = minimumOutputAmountSatoshis
        }
    }
}
