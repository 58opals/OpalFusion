// OpalFusion+Host+TransactionFinalizationProposal.swift

public extension OpalFusion.Host {
    struct TransactionFinalizationProposal: Sendable, Equatable {
        public let serializedUnsignedTransaction: [UInt8]

        public init(serializedUnsignedTransaction: [UInt8]) {
            self.serializedUnsignedTransaction = serializedUnsignedTransaction
        }
    }
}
