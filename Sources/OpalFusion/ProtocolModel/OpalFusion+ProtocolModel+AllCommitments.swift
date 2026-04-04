// OpalFusion+ProtocolModel+AllCommitments.swift

public extension OpalFusion.ProtocolModel {
    /// The full set of initial commitments repeated back by the coordinator.
    struct AllCommitments: Sendable, Equatable {
        public let initialCommitments: [OpalFusion.Commitment.InitialCommitment]

        public init(
            initialCommitments: [OpalFusion.Commitment.InitialCommitment]
        ) {
            self.initialCommitments = initialCommitments
        }
    }
}
