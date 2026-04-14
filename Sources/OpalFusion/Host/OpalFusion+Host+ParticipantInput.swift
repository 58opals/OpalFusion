// OpalFusion+Host+ParticipantInput.swift

public extension OpalFusion.Host {
    struct ParticipantInput: Sendable, Equatable {
        /// The 32-byte transaction identifier in standard display order.
        /// Reverse these bytes only when encoding BCH wire or protobuf fields.
        public let outpointTransactionHashBytes: [UInt8]
        public let outpointIndex: UInt32
        public let amountSatoshis: UInt64
        /// The full serialized BCH locking script bytecode for the reserved input.
        public let lockingScriptBytes: [UInt8]
        /// The compressed public key for the reserved input when the host can provide it.
        public let publicKey: [UInt8]?

        public init(
            outpointTransactionHashBytes: [UInt8],
            outpointIndex: UInt32,
            amountSatoshis: UInt64,
            lockingScriptBytes: [UInt8],
            publicKey: [UInt8]? = nil
        ) {
            self.outpointTransactionHashBytes = outpointTransactionHashBytes
            self.outpointIndex = outpointIndex
            self.amountSatoshis = amountSatoshis
            self.lockingScriptBytes = lockingScriptBytes
            self.publicKey = publicKey
        }
    }
}
