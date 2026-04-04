// OpalFusion+Commitment+OutputComponent.swift

public extension OpalFusion.Commitment {
    /// A transaction output payload contributed to a fusion round.
    struct OutputComponent: Sendable, Equatable {
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
