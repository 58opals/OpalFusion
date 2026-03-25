// OpalFusion+Host+FinalizedTransaction.swift

public extension OpalFusion.Host {
    struct FinalizedTransaction: Sendable, Equatable {
        public let serializedTransaction: [UInt8]

        public init(serializedTransaction: [UInt8]) {
            self.serializedTransaction = serializedTransaction
        }
    }
}
