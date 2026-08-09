// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~PreSignAcknowledgementSet.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodePreSignAcknowledgementSet(
        _ acknowledgementSet: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreSignAcknowledgementSet
    ) -> [UInt8] {
        acknowledgementSet.canonicalBytes
    }

    static func encodePreSignAcknowledgementSet(
        roundIdentifier: [UInt8],
        transcriptRoot: [UInt8],
        submissions: [OpalFusion.Mosaic.OpalMainnetAlpha
            .PreSignAcknowledgementSubmission]
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
        try encoder.writeFixedBytes(transcriptRoot, byteCount: 32)
        try encoder.writeVector(submissions) { encoder, submission in
            try encoder.writeFixedBytes(
                submission.acknowledgement.contributor.validatedBytes,
                byteCount: 32
            )
            try encoder.writeFixedBytes(
                submission.acknowledgement.rawRepresentation,
                byteCount: 64
            )
        }
        return encoder.encodedBytes
    }

    static func decodePreSignAcknowledgementSet(
        from encodedBytes: [UInt8],
        roster: OpalFusion.Mosaic.Attempt.Roster
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha
        .PreSignAcknowledgementSet {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
            let transcriptRoot = try decoder.readFixedBytes(byteCount: 32)
            let submissions = try decoder.readVector { decoder in
                try OpalFusion.Mosaic.OpalMainnetAlpha
                    .PreSignAcknowledgementSubmission(
                        contributor: .init(
                            validatedBytes: try decoder.readFixedBytes(
                                byteCount: 32
                            )
                        ),
                        roundIdentifier: roundIdentifier,
                        transcriptRoot: transcriptRoot,
                        signature: decoder.readFixedBytes(byteCount: 64)
                    )
            }
            return try .init(
                roundIdentifier: roundIdentifier,
                transcriptRoot: transcriptRoot,
                roster: roster,
                submissions: submissions
            )
        }
    }
}
