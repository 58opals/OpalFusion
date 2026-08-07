// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~GroupedCommitment.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodeGroupedCommitment(
        _ payload: OpalFusion.Mosaic.OpalV0.GroupedCommitmentPayload
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeVector(payload.commitments) { encoder, commitment in
            try writeComponentCommitment(commitment, to: &encoder)
        }
        encoder.writeUInt64(payload.excessFeeSatoshis)
        try encoder.writeFixedBytes(
            payload.pedersenTotalNonce,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        return encoder.encodedBytes
    }

    static func decodeGroupedCommitment(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.GroupedCommitmentPayload {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                commitments: decoder.readVector(
                    readingValueWith: readComponentCommitment
                ),
                excessFeeSatoshis: decoder.readUInt64(),
                pedersenTotalNonce: decoder.readFixedBytes(
                    byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                )
            )
        }
    }
}
