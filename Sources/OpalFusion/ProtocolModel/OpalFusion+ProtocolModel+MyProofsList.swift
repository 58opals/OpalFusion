// OpalFusion+ProtocolModel+MyProofsList.swift

public extension OpalFusion.ProtocolModel {
    /// The client's encrypted proof list and committed random number after round failure.
    struct MyProofsList: Sendable, Equatable {
        public let encryptedProofs: [[UInt8]]
        public let randomNumber: [UInt8]

        public init(
            encryptedProofs: [[UInt8]],
            randomNumber: [UInt8]
        ) {
            self.encryptedProofs = encryptedProofs
            self.randomNumber = randomNumber
        }
    }
}
