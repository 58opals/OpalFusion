// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~AggregateSet.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodeCommitmentSet(
        _ commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
    ) -> [UInt8] {
        commitmentSet.canonicalBytes
    }

    static func decodeCommitmentSet(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.CommitmentSet {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
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
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.ComponentSet {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                components: decoder.readSortedSet(
                    readingValueWith: readComponent
                )
            )
        }
    }
}
