// OpalFusion+BlindSignature+Response.swift

public extension OpalFusion.BlindSignature {
    /// A blind-signature response scalar returned by the coordinator.
    struct Response: Sendable, Equatable {
        public let scalar: [UInt8]

        public init(
            scalar: [UInt8]
        ) {
            self.scalar = scalar
        }
    }
}
