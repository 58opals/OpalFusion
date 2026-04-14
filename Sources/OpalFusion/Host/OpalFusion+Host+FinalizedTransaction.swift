// OpalFusion+Host+FinalizedTransaction.swift

public extension OpalFusion.Host {
    struct FinalizedTransaction: Sendable, Equatable {
        /// The full BCH wire-format finalized transaction bytes returned by the host.
        public let transactionBytes: [UInt8]

        public init(transactionBytes: [UInt8]) {
            self.transactionBytes = transactionBytes
        }
    }
}
