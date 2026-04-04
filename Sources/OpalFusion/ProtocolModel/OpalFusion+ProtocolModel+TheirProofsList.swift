// OpalFusion+ProtocolModel+TheirProofsList.swift

public extension OpalFusion.ProtocolModel {
    /// The coordinator's relayed proof list for blame validation.
    struct TheirProofsList: Sendable, Equatable {
        public let proofs: [OpalFusion.Blame.RelayedProof]

        public init(
            proofs: [OpalFusion.Blame.RelayedProof]
        ) {
            self.proofs = proofs
        }
    }
}
