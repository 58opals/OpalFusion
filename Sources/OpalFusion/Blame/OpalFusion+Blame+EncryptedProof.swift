// OpalFusion+Blame+EncryptedProof.swift

public extension OpalFusion.Blame {
    /// An encrypted proof payload awaiting relay or decryption.
    struct EncryptedProof: Sendable, Equatable {
        public let ciphertext: [UInt8]

        public init(
            ciphertext: [UInt8]
        ) {
            self.ciphertext = ciphertext
        }
    }
}
