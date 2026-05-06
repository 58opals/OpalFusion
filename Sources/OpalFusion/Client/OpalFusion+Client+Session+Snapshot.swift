// OpalFusion+Client+Session+Snapshot.swift

public extension OpalFusion.Client.Session {
    struct Snapshot: Sendable, Equatable {
        public struct CoordinatorStatus: Sendable, Equatable {
            public struct QueueStatus: Sendable, Equatable {
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

            public let updateSequence: UInt64
            public let latestInboundMessageKind: String?
            public let latestInboundPayloadByteCount: Int?
            public let queueStatus: QueueStatus?

            public init(
                updateSequence: UInt64 = 0,
                latestInboundMessageKind: String? = nil,
                latestInboundPayloadByteCount: Int? = nil,
                queueStatus: QueueStatus? = nil
            ) {
                self.updateSequence = updateSequence
                self.latestInboundMessageKind = latestInboundMessageKind
                self.latestInboundPayloadByteCount = latestInboundPayloadByteCount
                self.queueStatus = queueStatus
            }
        }

        public let state: OpalFusion.Client.State
        public let lastError: OpalFusion.Client.Error?
        public let lastErrorSummary: String?
        public let diagnostics: OpalFusion.Client.Diagnostics
        public let coordinatorStatus: CoordinatorStatus

        public init(
            state: OpalFusion.Client.State = .init(),
            lastError: OpalFusion.Client.Error? = nil,
            lastErrorSummary: String? = nil,
            diagnostics: OpalFusion.Client.Diagnostics = .init(),
            coordinatorStatus: CoordinatorStatus = .init()
        ) {
            self.state = state
            self.lastError = lastError
            self.lastErrorSummary = lastErrorSummary
            self.diagnostics = diagnostics
            self.coordinatorStatus = coordinatorStatus
        }
    }
}
