// OpalFusion+ProtocolModel+BlindSignatureResponses.swift

public extension OpalFusion.ProtocolModel {
    /// Blind-signature response scalars returned by the coordinator.
    struct BlindSignatureResponses: Sendable, Equatable {
        public let responses: [OpalFusion.BlindSignature.Response]

        public init(
            responses: [OpalFusion.BlindSignature.Response]
        ) {
            self.responses = responses
        }
    }
}
