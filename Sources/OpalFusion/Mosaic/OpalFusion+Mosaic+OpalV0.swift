// OpalFusion+Mosaic+OpalV0.swift

extension OpalFusion.Mosaic {
    /// Internal deterministic contracts for the non-live `Mosaic/0-opal.1` profile.
    enum OpalV0 {
        static let digestByteCount = 32
        static let amountCommitmentByteCount = 65
        static let communicationPublicKeyByteCount = 33
        static let componentCommitmentByteCount = digestByteCount
            + amountCommitmentByteCount
            + communicationPublicKeyByteCount
        static let authorizationMaterialByteCount = 256
        static let p2pkhLockingScriptByteCount = 25
        static let maximumMoneySatoshis: UInt64 = 2_100_000_000_000_000
        static let componentAuthorizationCountPerContributor = 23
        static let paddedInnerPlaintextByteCount = OpalFusion.Mosaic
            .PaddedEnvelopeCodec.encodedByteCount
        static let maximumInnerPayloadByteCount = OpalFusion.Mosaic
            .PaddedEnvelopeCodec.maximumPayloadByteCount
        static let aggregateFragmentHeaderByteCount = digestByteCount
            + 1
            + digestByteCount
            + 4
            + 1
            + 1
            + 4
        static let maximumAggregateFragmentBodyByteCount =
            maximumInnerPayloadByteCount - aggregateFragmentHeaderByteCount
        static let maximumAggregateDocumentByteCount = 4
            + (OpalFusion.Mosaic.RosterPolicy.opalV0.maximumCandidateCount
                - OpalFusion.Mosaic.RosterPolicy.opalV0.conductorCount)
            * componentAuthorizationCountPerContributor
            * componentCommitmentByteCount
        static let maximumAggregateFragmentCount =
            (maximumAggregateDocumentByteCount
                + maximumAggregateFragmentBodyByteCount - 1)
            / maximumAggregateFragmentBodyByteCount
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
