// OpalFusion+Client+Session+Snapshot+CoordinatorStatus+TierQueue.swift

public extension OpalFusion.Client.Session.Snapshot.CoordinatorStatus {
    struct TierQueue: Sendable, Equatable {
        public let tierSatoshis: UInt64
        public let players: UInt32?
        public let minPlayers: UInt32?
        public let maxPlayers: UInt32?
        public let timeRemaining: UInt32?

        public init(
            tierSatoshis: UInt64,
            players: UInt32? = nil,
            minPlayers: UInt32? = nil,
            maxPlayers: UInt32? = nil,
            timeRemaining: UInt32? = nil
        ) {
            self.tierSatoshis = tierSatoshis
            self.players = players
            self.minPlayers = minPlayers
            self.maxPlayers = maxPlayers
            self.timeRemaining = timeRemaining
        }
    }
}
