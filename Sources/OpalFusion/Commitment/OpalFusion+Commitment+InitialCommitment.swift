// OpalFusion+Commitment+InitialCommitment.swift

public extension OpalFusion.Commitment {
    /// The initial commitment bundle submitted before full component reveal.
    struct InitialCommitment: Sendable, Equatable {
        public let saltedComponentHash: [UInt8]
        public let amountCommitment: [UInt8]
        public let communicationPublicKey: [UInt8]

        public init(
            saltedComponentHash: [UInt8],
            amountCommitment: [UInt8],
            communicationPublicKey: [UInt8]
        ) {
            self.saltedComponentHash = saltedComponentHash
            self.amountCommitment = amountCommitment
            self.communicationPublicKey = communicationPublicKey
        }
    }
}
