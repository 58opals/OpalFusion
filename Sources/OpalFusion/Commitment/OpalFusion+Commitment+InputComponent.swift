// OpalFusion+Commitment+InputComponent.swift

public extension OpalFusion.Commitment {
    /// A transaction input payload contributed to a fusion round.
    struct InputComponent: Sendable, Equatable {
        public let outpointTransactionHash: [UInt8]
        public let outpointIndex: UInt32
        public let publicKey: [UInt8]
        public let amountSatoshis: UInt64

        public init(
            outpointTransactionHash: [UInt8],
            outpointIndex: UInt32,
            publicKey: [UInt8],
            amountSatoshis: UInt64
        ) {
            self.outpointTransactionHash = outpointTransactionHash
            self.outpointIndex = outpointIndex
            self.publicKey = publicKey
            self.amountSatoshis = amountSatoshis
        }
    }
}
