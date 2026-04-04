// OpalFusion+ProtocolModel+Blames.swift

public extension OpalFusion.ProtocolModel {
    /// The client's finalized blame submissions for the current failed round.
    struct Blames: Sendable, Equatable {
        public let blames: [OpalFusion.Blame.BlameProof]

        public init(
            blames: [OpalFusion.Blame.BlameProof]
        ) {
            self.blames = blames
        }
    }
}
