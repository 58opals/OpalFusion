// OpalFusion+ProtocolModel+FusionResult.swift

public extension OpalFusion.ProtocolModel {
    /// The coordinator's terminal outcome payload for a happy-path round attempt.
    struct FusionResult: Sendable, Equatable {
        public let isSuccess: Bool
        public let transactionSignatures: [[UInt8]]
        public let badComponentIndices: [UInt32]

        public init(
            isSuccess: Bool,
            transactionSignatures: [[UInt8]],
            badComponentIndices: [UInt32]
        ) {
            self.isSuccess = isSuccess
            self.transactionSignatures = transactionSignatures
            self.badComponentIndices = badComponentIndices
        }
    }
}
