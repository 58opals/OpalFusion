// OpalFusion+Host+ParticipantOutput.swift

public extension OpalFusion.Host {
    struct ParticipantOutput: Sendable, Equatable {
        public let lockingScript: [UInt8]
        public let amountSatoshis: UInt64

        public init(
            lockingScript: [UInt8],
            amountSatoshis: UInt64
        ) {
            self.lockingScript = lockingScript
            self.amountSatoshis = amountSatoshis
        }
    }
}
