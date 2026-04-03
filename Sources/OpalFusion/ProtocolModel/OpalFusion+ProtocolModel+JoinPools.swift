// OpalFusion+ProtocolModel+JoinPools.swift

public extension OpalFusion.ProtocolModel {
    /// A client's requested tiers and pool tags for queue entry.
    struct JoinPools: Sendable, Equatable {
        /// `fusion.proto` `JoinPools.tiers`.
        public let tiers: [UInt64]
        /// `fusion.proto` `JoinPools.tags`.
        public let tags: [OpalFusion.ProtocolModel.PoolTag]

        public init(
            tiers: [UInt64],
            tags: [OpalFusion.ProtocolModel.PoolTag]
        ) {
            self.tiers = tiers
            self.tags = tags
        }
    }
}
