// OpalFusion+Client+State.swift

public extension OpalFusion.Client {
    struct State: Sendable, Equatable {
        public let isConnected: Bool
        public let round: OpalFusion.Round.State?

        public init(
            isConnected: Bool = false,
            round: OpalFusion.Round.State? = nil
        ) {
            self.isConnected = isConnected
            self.round = round
        }
    }
}
