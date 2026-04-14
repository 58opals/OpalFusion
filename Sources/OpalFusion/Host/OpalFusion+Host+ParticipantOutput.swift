// OpalFusion+Host+ParticipantOutput.swift

public extension OpalFusion.Host {
    struct ParticipantOutput: Sendable, Equatable {
        /// The full serialized BCH locking script bytecode for the reserved output.
        public let lockingScriptBytes: [UInt8]
        public let amountSatoshis: UInt64

        public init(
            lockingScriptBytes: [UInt8],
            amountSatoshis: UInt64
        ) {
            self.lockingScriptBytes = lockingScriptBytes
            self.amountSatoshis = amountSatoshis
        }
    }
}
