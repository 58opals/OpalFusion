// OpalFusion+Mosaic+OpalV0+CanonicalWireCodec~AnonymousComponent.swift

extension OpalFusion.Mosaic.OpalV0.CanonicalWireCodec {
    static func encodeAnonymousComponent(
        _ payload: OpalFusion.Mosaic.OpalV0.AnonymousComponentPayload
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(
            payload.roundIdentifier,
            byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
        )
        try writeAuthorizationToken(
            payload.authorizationToken,
            to: &encoder
        )
        try writeComponent(payload.component, to: &encoder)
        return encoder.encodedBytes
    }

    static func decodeAnonymousComponent(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalV0.AnonymousComponentPayload {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                roundIdentifier: decoder.readFixedBytes(
                    byteCount: OpalFusion.Mosaic.OpalV0.digestByteCount
                ),
                authorizationToken: readAuthorizationToken(from: &decoder),
                component: readComponent(from: &decoder)
            )
        }
    }
}
