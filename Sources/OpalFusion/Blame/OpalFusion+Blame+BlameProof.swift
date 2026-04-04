// OpalFusion+Blame+BlameProof.swift

public extension OpalFusion.Blame {
    /// A single blame claim tied to a previously relayed proof.
    struct BlameProof: Sendable, Equatable {
        public let proofIndex: UInt32
        public let decrypter: OpalFusion.Blame.Decrypter
        public let requiresBlockchainLookup: Bool?
        public let reason: String?

        public init(
            proofIndex: UInt32,
            decrypter: OpalFusion.Blame.Decrypter,
            requiresBlockchainLookup: Bool? = nil,
            reason: String? = nil
        ) {
            self.proofIndex = proofIndex
            self.decrypter = decrypter
            self.requiresBlockchainLookup = requiresBlockchainLookup
            self.reason = reason
        }
    }
}
