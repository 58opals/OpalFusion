// OpalFusion+Mosaic+RuntimeSession+MessageIdentifier.swift

extension OpalFusion.Mosaic.RuntimeSession {
    struct MessageIdentifier: Sendable, Hashable {
        let bytes: [UInt8]

        init(bytes: [UInt8]) throws {
            guard bytes.count == 32 else {
                throw ValidationError.invalidByteCount(actual: bytes.count)
            }
            self.bytes = bytes
        }
    }
}
