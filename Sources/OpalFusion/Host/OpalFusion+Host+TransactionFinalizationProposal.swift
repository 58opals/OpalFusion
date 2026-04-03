// OpalFusion+Host+TransactionFinalizationProposal.swift

public extension OpalFusion.Host {
    /// A host-facing proposal describing the transaction OpalFusion expects the host to finalize.
    struct TransactionFinalizationProposal: Sendable, Equatable {
        /// The serialized unsigned transaction bytes derived from the current round.
        public let serializedUnsignedTransaction: [UInt8]
        /// The server-provided session hash, when available for cross-checking.
        public let sessionHash: [UInt8]?
        /// The expected transaction input count implied by the shared round components.
        public let expectedInputCount: Int?
        /// The expected transaction output count implied by the shared round components.
        public let expectedOutputCount: Int?
        /// The participant count known for the round, when available.
        public let participantCount: Int?

        public init(
            serializedUnsignedTransaction: [UInt8],
            sessionHash: [UInt8]? = nil,
            expectedInputCount: Int? = nil,
            expectedOutputCount: Int? = nil,
            participantCount: Int? = nil
        ) {
            self.serializedUnsignedTransaction = serializedUnsignedTransaction
            self.sessionHash = sessionHash
            self.expectedInputCount = expectedInputCount
            self.expectedOutputCount = expectedOutputCount
            self.participantCount = participantCount
        }
    }
}
