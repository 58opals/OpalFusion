// OpalFusion+Host+Event.swift

public extension OpalFusion.Host {
    struct Event: Sendable, Equatable {
        public let phase: OpalFusion.Round.Phase
        public let summary: String
        public let isTerminal: Bool

        public init(
            phase: OpalFusion.Round.Phase,
            summary: String,
            isTerminal: Bool = false
        ) {
            self.phase = phase
            self.summary = summary
            self.isTerminal = isTerminal
        }
    }
}
