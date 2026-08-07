// OpalFusion+Mosaic+OpalV0.swift

extension OpalFusion.Mosaic {
    /// Internal deterministic contracts for the non-live `Mosaic/0-opal.1` profile.
    enum OpalV0 {
        static let componentAuthorizationCountPerContributor = 23
        static let paddedInnerPlaintextByteCount = 8_192
        static let maximumInnerPayloadByteCount = 4_092
        static let nip44ContentByteCount = 11_012
        static let maximumEventJSONByteCount = 16_384
        static let chipnetGenesisHash: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x1d, 0xd4, 0x10, 0xc4,
            0x9a, 0x78, 0x86, 0x68, 0xce, 0x26, 0x75, 0x17,
            0x18, 0xcc, 0x79, 0x74, 0x74, 0xd3, 0x15, 0x2a,
            0x5f, 0xc0, 0x73, 0xdd, 0x44, 0xfd, 0x9f, 0x7b
        ]
    }
}
