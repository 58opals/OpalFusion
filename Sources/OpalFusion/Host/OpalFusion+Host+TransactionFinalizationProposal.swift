// OpalFusion+Host+TransactionFinalizationProposal.swift

public extension OpalFusion.Host {
    /// A host-facing proposal describing the transaction OpalFusion expects the host to finalize.
    struct TransactionFinalizationProposal: Sendable, Equatable {
        /// The full BCH wire-format unsigned transaction bytes derived from the current round.
        public let unsignedTransactionBytes: [UInt8]
        /// The server-provided session hash, when available for cross-checking.
        public let sessionHash: [UInt8]?
        /// The expected transaction input count implied by the shared round components.
        public let expectedInputCount: Int?
        /// The expected transaction output count implied by the shared round components.
        public let expectedOutputCount: Int?
        /// The participant count known for the round, when available.
        public let participantCount: Int?

        public init(
            unsignedTransactionBytes: [UInt8],
            sessionHash: [UInt8]? = nil,
            expectedInputCount: Int? = nil,
            expectedOutputCount: Int? = nil,
            participantCount: Int? = nil
        ) {
            self.unsignedTransactionBytes = unsignedTransactionBytes
            self.sessionHash = sessionHash
            self.expectedInputCount = expectedInputCount
            self.expectedOutputCount = expectedOutputCount
            self.participantCount = participantCount
        }
    }
}
