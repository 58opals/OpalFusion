// OpalFusion+ProtocolModel+PoolTag.swift

public extension OpalFusion.ProtocolModel {
    /// A pool-participation tag used to limit self-collisions across tiers.
    struct PoolTag: Sendable, Equatable {
        /// `fusion.proto` `JoinPools.PoolTag.id`.
        public let identifier: [UInt8]
        /// `fusion.proto` `JoinPools.PoolTag.limit`.
        public let limit: UInt32
        /// `fusion.proto` `JoinPools.PoolTag.no_ip`.
        public let noIp: Bool?

        public init(
            identifier: [UInt8],
            limit: UInt32,
            noIp: Bool? = nil
        ) {
            self.identifier = identifier
            self.limit = limit
            self.noIp = noIp
        }
    }
}
