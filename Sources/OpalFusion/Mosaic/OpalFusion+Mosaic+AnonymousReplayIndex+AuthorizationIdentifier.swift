// OpalFusion+Mosaic+AnonymousReplayIndex+AuthorizationIdentifier.swift

extension OpalFusion.Mosaic.AnonymousReplayIndex {
    struct AuthorizationIdentifier: Sendable, Hashable {
        let validatedBytes: [UInt8]

        init(validatedBytes: [UInt8]) {
            self.validatedBytes = validatedBytes
        }
    }
}
