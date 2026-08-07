// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~Commitment.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodeComponentCommitment(
        _ commitment: OpalFusion.Mosaic.OpalV0.ComponentCommitment
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try writeComponentCommitment(commitment, to: &encoder)
        return encoder.encodedBytes
    }

    static func decodeComponentCommitment(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.ComponentCommitment {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(
            from: encodedBytes,
            readingValueWith: readComponentCommitment
        )
    }

    static func writeComponentCommitment(
        _ commitment: OpalFusion.Mosaic.OpalV0.ComponentCommitment,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        try encoder.writeFixedBytes(
            commitment.saltedComponentDigest,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            commitment.amountCommitment,
            byteCount: OpalFusion.Mosaic.OpalV0.amountCommitmentByteCount
        )
        try encoder.writeFixedBytes(
            commitment.communicationPublicKey,
            byteCount: OpalFusion.Mosaic.OpalV0.communicationPublicKeyByteCount
        )
    }

    static func readComponentCommitment(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.Mosaic.OpalV0.ComponentCommitment {
        try .init(
            saltedComponentDigest: decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
            ),
            amountCommitment: decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.amountCommitmentByteCount
            ),
            communicationPublicKey: decoder.readFixedBytes(
                byteCount: OpalFusion.Mosaic.OpalV0.communicationPublicKeyByteCount
            )
        )
    }
}
