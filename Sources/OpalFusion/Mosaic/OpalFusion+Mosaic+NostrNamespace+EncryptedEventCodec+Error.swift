// OpalFusion+Mosaic+NostrNamespace+EncryptedEventCodec+Error.swift

extension OpalFusion.Mosaic.NostrNamespace.EncryptedEventCodec {
    enum Error: Swift.Error, Sendable, Equatable {
        case unexpectedKind(expected: UInt16, actual: UInt16)
        case unexpectedSender
    }
}
