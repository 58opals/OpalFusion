// OpalFusion+Blame+Decrypter.swift

public extension OpalFusion.Blame {
    /// The secret material a client reveals when substantiating a blame claim.
    enum Decrypter: Sendable, Equatable {
        case sessionKey([UInt8])
        case privateKey([UInt8])
    }
}
