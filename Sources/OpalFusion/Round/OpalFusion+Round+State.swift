// OpalFusion+Round+State.swift

public extension OpalFusion.Round {
    /// A coarse public snapshot of a CashFusion round.
    struct State: Sendable, Equatable {
        public let identifier: OpalFusion.Round.Identifier
        public let phase: OpalFusion.Round.Phase
        public let participantCount: Int?
        /// A terminal round outcome when the round has completed, otherwise `nil`.
        public let completionStatus: OpalFusion.Round.CompletionStatus?
        public var isTerminal: Bool { completionStatus != nil }

        public init(
            identifier: OpalFusion.Round.Identifier,
            phase: OpalFusion.Round.Phase,
            participantCount: Int? = nil
        ) {
            self.identifier = identifier
            self.phase = phase
            self.participantCount = participantCount
            self.completionStatus = nil
        }

        public init(
            identifier: OpalFusion.Round.Identifier,
            participantCount: Int? = nil,
            completionStatus: OpalFusion.Round.CompletionStatus
        ) {
            self.identifier = identifier
            self.phase = .completed
            self.participantCount = participantCount
            self.completionStatus = completionStatus
        }
    }
}
