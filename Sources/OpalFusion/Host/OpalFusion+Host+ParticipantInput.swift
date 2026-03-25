// OpalFusion+Host+ParticipantInput.swift

public extension OpalFusion.Host {
    struct ParticipantInput: Sendable, Equatable {
        public let outpointTransactionHash: [UInt8]
        public let outpointIndex: UInt32
        public let amountSatoshis: UInt64
        public let lockingScript: [UInt8]

        public init(
            outpointTransactionHash: [UInt8],
            outpointIndex: UInt32,
            amountSatoshis: UInt64,
            lockingScript: [UInt8]
        ) {
            self.outpointTransactionHash = outpointTransactionHash
            self.outpointIndex = outpointIndex
            self.amountSatoshis = amountSatoshis
            self.lockingScript = lockingScript
        }
    }
}
