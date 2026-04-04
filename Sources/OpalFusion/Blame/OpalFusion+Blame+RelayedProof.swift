// OpalFusion+Blame+RelayedProof.swift

public extension OpalFusion.Blame {
    /// A proof relayed by the coordinator to a specific recipient key index.
    struct RelayedProof: Sendable, Equatable {
        public let encryptedProof: [UInt8]
        public let sourceCommitmentIndex: UInt32
        public let destinationKeyIndex: UInt32

        public init(
            encryptedProof: [UInt8],
            sourceCommitmentIndex: UInt32,
            destinationKeyIndex: UInt32
        ) {
            self.encryptedProof = encryptedProof
            self.sourceCommitmentIndex = sourceCommitmentIndex
            self.destinationKeyIndex = destinationKeyIndex
        }
    }
}
