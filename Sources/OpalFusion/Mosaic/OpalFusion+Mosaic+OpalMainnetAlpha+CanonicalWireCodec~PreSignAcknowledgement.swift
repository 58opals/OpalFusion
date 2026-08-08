// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~PreSignAcknowledgement.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodePreSignAcknowledgementSubmission(
        _ submission: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreSignAcknowledgementSubmission
    ) -> [UInt8] {
        submission.canonicalBytes
    }

    static func encodePreSignAcknowledgementSubmission(
        roundIdentifier: [UInt8],
        transcriptRoot: [UInt8],
        signature: [UInt8]
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
        try encoder.writeFixedBytes(transcriptRoot, byteCount: 32)
        try encoder.writeFixedBytes(signature, byteCount: 64)
        return encoder.encodedBytes
    }

    static func decodePreSignAcknowledgementSubmission(
        from encodedBytes: [UInt8],
        contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha
        .PreSignAcknowledgementSubmission {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                contributor: contributor,
                roundIdentifier: decoder.readFixedBytes(byteCount: 32),
                transcriptRoot: decoder.readFixedBytes(byteCount: 32),
                signature: decoder.readFixedBytes(byteCount: 64)
            )
        }
    }
}
