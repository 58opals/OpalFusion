// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~BCHSignature.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeBCHSignatureSubmission(
        _ submission: OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureSubmission
    ) -> [UInt8] {
        submission.canonicalBytes
    }

    static func encodeBCHSignatureSubmission(
        transcriptRoot: [UInt8],
        authorizationToken: OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationToken,
        entry: OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureEntry
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(transcriptRoot, byteCount: 32)
        try writeAuthorizationToken(authorizationToken, to: &encoder)
        try writeBCHSignatureEntry(entry, to: &encoder)
        return encoder.encodedBytes
    }

    static func decodeBCHSignatureSubmission(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureSubmission {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                transcriptRoot: decoder.readFixedBytes(byteCount: 32),
                authorizationToken: readAuthorizationToken(from: &decoder),
                entry: readBCHSignatureEntry(from: &decoder)
            )
        }
    }

    static func encodeBCHSignatureSet(
        _ signatureSet: OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureSet
    ) -> [UInt8] {
        signatureSet.canonicalBytes
    }

    static func encodeBCHSignatureSet(
        roundIdentifier: [UInt8],
        transcriptRoot: [UInt8],
        entries: [OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureEntry]
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
        try encoder.writeFixedBytes(transcriptRoot, byteCount: 32)
        try encoder.writeVector(entries) { encoder, entry in
            try writeBCHSignatureEntry(entry, to: &encoder)
        }
        return encoder.encodedBytes
    }

    static func decodeBCHSignatureSet(
        from encodedBytes: [UInt8],
        expectedInputCount: Int
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureSet {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            let roundIdentifier = try decoder.readFixedBytes(byteCount: 32)
            let transcriptRoot = try decoder.readFixedBytes(byteCount: 32)
            let entries = try decoder.readVector(
                readingValueWith: readBCHSignatureEntry
            )
            for index in entries.indices.dropFirst() {
                let previous = entries[index - 1].inputIndex
                let current = entries[index].inputIndex
                guard previous < current else {
                    if previous == current {
                        throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                            .duplicateSignatureInputIndex(current)
                    }
                    throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError
                        .nonCanonicalSignatureOrder
                }
            }
            return try .init(
                roundIdentifier: roundIdentifier,
                transcriptRoot: transcriptRoot,
                entries: entries,
                expectedInputCount: expectedInputCount
            )
        }
    }

    private static func writeBCHSignatureEntry(
        _ entry: OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureEntry,
        to encoder: inout OpalFusion.Mosaic.CanonicalEncoder
    ) throws {
        encoder.writeUInt32(entry.inputIndex)
        try encoder.writeFixedBytes(entry.signature, byteCount: 64)
        try encoder.writeFixedBytes(entry.publicKey, byteCount: 33)
    }

    private static func readBCHSignatureEntry(
        from decoder: inout OpalFusion.Mosaic.CanonicalDecoder
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureEntry {
        try .init(
            inputIndex: decoder.readUInt32(),
            signature: decoder.readFixedBytes(byteCount: 64),
            publicKey: decoder.readFixedBytes(byteCount: 33)
        )
    }
}
