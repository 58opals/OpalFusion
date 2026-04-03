// OpalFusion+Host+Event.swift

public extension OpalFusion.Host {
    /// A coarse host-observable event emitted while a CashFusion round progresses.
    struct Event: Sendable, Equatable {
        /// A coarse event category suitable for host-facing logging and state updates.
        public let kind: OpalFusion.Host.Event.Kind
        /// The public round phase associated with the event.
        public let phase: OpalFusion.Round.Phase
        /// A human-readable summary intended for host integration surfaces.
        public let summary: String
        /// Indicates whether this event represents a terminal round outcome.
        public let isTerminal: Bool

        public init(
            kind: OpalFusion.Host.Event.Kind = .status,
            phase: OpalFusion.Round.Phase,
            summary: String,
            isTerminal: Bool = false
        ) {
            self.kind = kind
            self.phase = phase
            self.summary = summary
            self.isTerminal = isTerminal
        }
    }
}
