// OpalFusion+Blame+Proof.swift

public extension OpalFusion.Blame {
    /// A decrypted proof payload describing one disputed component.
    struct Proof: Sendable, Equatable {
        public let componentIndex: UInt32
        public let salt: [UInt8]
        public let pedersenNonce: [UInt8]

        public init(
            componentIndex: UInt32,
            salt: [UInt8],
            pedersenNonce: [UInt8]
        ) {
            self.componentIndex = componentIndex
            self.salt = salt
            self.pedersenNonce = pedersenNonce
        }
    }
}
