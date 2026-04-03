// OpalFusion+ProtocolModel+ClientHello.swift

public extension OpalFusion.ProtocolModel {
    /// The client's initial protocol greeting on the primary channel.
    struct ClientHello: Sendable, Equatable {
        /// `fusion.proto` `ClientHello.version`.
        public let versionBytes: [UInt8]
        /// `fusion.proto` `ClientHello.genesis_hash`.
        public let genesisHash: [UInt8]?

        public init(
            versionBytes: [UInt8],
            genesisHash: [UInt8]? = nil
        ) {
            self.versionBytes = versionBytes
            self.genesisHash = genesisHash
        }
    }
}
