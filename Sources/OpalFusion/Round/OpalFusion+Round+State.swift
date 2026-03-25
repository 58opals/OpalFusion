// OpalFusion+Round+State.swift

public extension OpalFusion.Round {
    struct State: Sendable, Equatable {
        public let identifier: OpalFusion.Round.Identifier
        public let phase: OpalFusion.Round.Phase
        public let participantCount: Int?
        public let isTerminal: Bool

        public init(
            identifier: OpalFusion.Round.Identifier,
            phase: OpalFusion.Round.Phase,
            participantCount: Int? = nil,
            isTerminal: Bool = false
        ) {
            self.identifier = identifier
            self.phase = phase
            self.participantCount = participantCount
            self.isTerminal = isTerminal
        }
    }
}
