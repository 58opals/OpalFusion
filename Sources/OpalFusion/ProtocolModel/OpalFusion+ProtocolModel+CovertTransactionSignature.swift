// OpalFusion+ProtocolModel+CovertTransactionSignature.swift

public extension OpalFusion.ProtocolModel {
    /// A covertly submitted transaction signature for one round input.
    struct CovertTransactionSignature: Sendable, Equatable {
        public let roundPublicKey: [UInt8]?
        public let inputIndex: UInt32
        public let transactionSignature: [UInt8]

        public init(
            roundPublicKey: [UInt8]? = nil,
            inputIndex: UInt32,
            transactionSignature: [UInt8]
        ) {
            self.roundPublicKey = roundPublicKey
            self.inputIndex = inputIndex
            self.transactionSignature = transactionSignature
        }
    }
}
