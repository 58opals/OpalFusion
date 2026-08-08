// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~AggregateSet.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodeCommitmentSet(
        _ commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
    ) -> [UInt8] {
        commitmentSet.canonicalBytes
    }

    static func decodeCommitmentSet(
        from encodedBytes: [UInt8],
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> OpalFusion.Mosaic.OpalV0.CommitmentSet {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                profile: profile,
                commitments: decoder.readSortedSet(
                    readingValueWith: readComponentCommitment
                )
            )
        }
    }

    static func encodeComponentSet(
        _ componentSet: OpalFusion.Mosaic.OpalV0.ComponentSet
    ) -> [UInt8] {
        componentSet.canonicalBytes
    }

    static func decodeComponentSet(
        from encodedBytes: [UInt8],
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> OpalFusion.Mosaic.OpalV0.ComponentSet {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                profile: profile,
                components: decoder.readSortedSet(
                    readingValueWith: readComponent
                )
            )
        }
    }
}
