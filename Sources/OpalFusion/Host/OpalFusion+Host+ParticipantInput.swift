// OpalFusion+Host+ParticipantInput.swift

public extension OpalFusion.Host {
    struct ParticipantInput: Sendable, Equatable {
        public let outpointTransactionHash: [UInt8]
        public let outpointIndex: UInt32
        public let amountSatoshis: UInt64
        public let lockingScript: [UInt8]
        /// The compressed public key for the reserved input when the host can provide it.
        public let publicKey: [UInt8]?

        public init(
            outpointTransactionHash: [UInt8],
            outpointIndex: UInt32,
            amountSatoshis: UInt64,
            lockingScript: [UInt8],
            publicKey: [UInt8]? = nil
        ) {
            self.outpointTransactionHash = outpointTransactionHash
            self.outpointIndex = outpointIndex
            self.amountSatoshis = amountSatoshis
            self.lockingScript = lockingScript
            self.publicKey = publicKey
        }
    }
}
