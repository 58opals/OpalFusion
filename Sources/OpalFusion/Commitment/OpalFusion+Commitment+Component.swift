// OpalFusion+Commitment+Component.swift

public extension OpalFusion.Commitment {
    /// A committed component paired with its salt commitment.
    struct Component: Sendable, Equatable {
        public let saltCommitment: [UInt8]
        public let payload: OpalFusion.Commitment.ComponentPayload

        public init(
            saltCommitment: [UInt8],
            payload: OpalFusion.Commitment.ComponentPayload
        ) {
            self.saltCommitment = saltCommitment
            self.payload = payload
        }
    }
}
