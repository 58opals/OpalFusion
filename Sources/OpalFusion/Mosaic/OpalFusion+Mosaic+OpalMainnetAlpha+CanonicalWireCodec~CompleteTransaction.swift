// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~CompleteTransaction.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeCompleteTransactionPayload(
        _ payload: OpalFusion.Mosaic.OpalMainnetAlpha.CompleteTransactionPayload
    ) -> [UInt8] {
        payload.canonicalBytes
    }

    static func encodeCompleteTransactionPayload(
        roundIdentifier: [UInt8],
        transcriptRoot: [UInt8],
        transactionBytes: [UInt8]
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(roundIdentifier, byteCount: 32)
        try encoder.writeFixedBytes(transcriptRoot, byteCount: 32)
        try encoder.writeBytes(transactionBytes)
        return encoder.encodedBytes
    }

    static func decodeCompleteTransactionPayload(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.CompleteTransactionPayload {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                roundIdentifier: decoder.readFixedBytes(byteCount: 32),
                transcriptRoot: decoder.readFixedBytes(byteCount: 32),
                completeTransaction: OpalFusion.Host.MosaicCompleteTransaction(
                    transactionBytes: decoder.readBytes()
                )
            )
        }
    }
}
