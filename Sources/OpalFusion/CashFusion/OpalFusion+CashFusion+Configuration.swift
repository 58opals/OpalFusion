// OpalFusion+CashFusion+Configuration.swift

public extension OpalFusion.CashFusion {
    /// The values required to configure the live CashFusion client engine.
    struct Configuration: Sendable, Equatable {
        public let coordinator: OpalFusion.Client.Configuration
        public let genesisHash: [UInt8]?
        public let joinPools: OpalFusion.ProtocolModel.JoinPools
        public let reconnectPolicy: OpalFusion.Client.ReconnectPolicy

        public init(
            coordinator: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            reconnectPolicy: OpalFusion.Client.ReconnectPolicy = .disabled
        ) {
            self.coordinator = coordinator
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.reconnectPolicy = reconnectPolicy
        }
    }
}
