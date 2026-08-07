// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~PreSignAcknowledgement.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodePreSignAcknowledgement(
        _ payload: OpalFusion.Mosaic.OpalV0.PreSignAcknowledgementPayload
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(
            payload.roundIdentifier,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try encoder.writeFixedBytes(
            payload.transcriptRoot,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        return encoder.encodedBytes
    }

    static func decodePreSignAcknowledgement(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.PreSignAcknowledgementPayload {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                roundIdentifier: decoder.readFixedBytes(
                    byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                ),
                transcriptRoot: decoder.readFixedBytes(
                    byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                )
            )
        }
    }
}
