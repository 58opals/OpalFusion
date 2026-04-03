// OpalFusion+ProtocolModel+TierStatus.swift

public extension OpalFusion.ProtocolModel {
    /// Server-reported queue state for one tier.
    struct TierStatus: Sendable, Equatable {
        /// `fusion.proto` `TierStatus.players`.
        public let playerCount: UInt32?
        /// `fusion.proto` `TierStatus.min_players`.
        public let minimumPlayerCount: UInt32?
        /// `fusion.proto` `TierStatus.max_players`.
        public let maximumPlayerCount: UInt32?
        /// `fusion.proto` `TierStatus.time_remaining`.
        public let timeRemainingSeconds: UInt32?

        public init(
            playerCount: UInt32? = nil,
            minimumPlayerCount: UInt32? = nil,
            maximumPlayerCount: UInt32? = nil,
            timeRemainingSeconds: UInt32? = nil
        ) {
            self.playerCount = playerCount
            self.minimumPlayerCount = minimumPlayerCount
            self.maximumPlayerCount = maximumPlayerCount
            self.timeRemainingSeconds = timeRemainingSeconds
        }
    }
}
