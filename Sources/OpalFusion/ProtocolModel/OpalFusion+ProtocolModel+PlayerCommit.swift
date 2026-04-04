// OpalFusion+ProtocolModel+PlayerCommit.swift

public extension OpalFusion.ProtocolModel {
    /// The client's commitment-phase submission at the start of a round.
    struct PlayerCommit: Sendable, Equatable {
        public let initialCommitments: [OpalFusion.Commitment.InitialCommitment]
        public let excessFeeSatoshis: UInt64
        public let pedersenTotalNonce: [UInt8]
        public let randomNumberCommitment: [UInt8]
        public let blindSignatureRequests: [OpalFusion.BlindSignature.Request]

        public init(
            initialCommitments: [OpalFusion.Commitment.InitialCommitment],
            excessFeeSatoshis: UInt64,
            pedersenTotalNonce: [UInt8],
            randomNumberCommitment: [UInt8],
            blindSignatureRequests: [OpalFusion.BlindSignature.Request]
        ) {
            self.initialCommitments = initialCommitments
            self.excessFeeSatoshis = excessFeeSatoshis
            self.pedersenTotalNonce = pedersenTotalNonce
            self.randomNumberCommitment = randomNumberCommitment
            self.blindSignatureRequests = blindSignatureRequests
        }
    }
}
