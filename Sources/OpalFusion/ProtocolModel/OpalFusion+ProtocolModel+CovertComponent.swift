// OpalFusion+ProtocolModel+CovertComponent.swift

public extension OpalFusion.ProtocolModel {
    /// A covertly submitted component payload signed for the current round.
    struct CovertComponent: Sendable, Equatable {
        public let roundPublicKey: [UInt8]?
        public let signature: [UInt8]
        public let serializedComponent: [UInt8]

        public init(
            roundPublicKey: [UInt8]? = nil,
            signature: [UInt8],
            serializedComponent: [UInt8]
        ) {
            self.roundPublicKey = roundPublicKey
            self.signature = signature
            self.serializedComponent = serializedComponent
        }
    }
}
