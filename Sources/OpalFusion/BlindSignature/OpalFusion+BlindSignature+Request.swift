// OpalFusion+BlindSignature+Request.swift

public extension OpalFusion.BlindSignature {
    /// A blind-signature request scalar submitted during round setup.
    struct Request: Sendable, Equatable {
        public let scalar: [UInt8]

        public init(
            scalar: [UInt8]
        ) {
            self.scalar = scalar
        }
    }
}
