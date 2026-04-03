// OpalFusion+ProtocolModel+TierStatusUpdate.swift

public extension OpalFusion.ProtocolModel {
    /// The server's latest queue snapshot across tiers.
    struct TierStatusUpdate: Sendable, Equatable {
        /// `fusion.proto` `TierStatusUpdate.statuses`.
        public let statusesByTier: [UInt64: OpalFusion.ProtocolModel.TierStatus]

        public init(
            statusesByTier: [UInt64: OpalFusion.ProtocolModel.TierStatus]
        ) {
            self.statusesByTier = statusesByTier
        }
    }
}
