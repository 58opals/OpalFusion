// OpalFusion+Mosaic+OpalMainnetAlpha+CanonicalWireCodec~AnonymousComponent.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.CanonicalWireCodec {
    static func encodeAnonymousComponent(
        _ payload: OpalFusion.Mosaic.OpalMainnetAlpha.AnonymousComponentPayload
    ) throws -> [UInt8] {
        var encoder = OpalFusion.Mosaic.CanonicalEncoder()
        try encoder.writeFixedBytes(payload.roundIdentifier, byteCount: 32)
        try writeAuthorizationToken(payload.authorizationToken, to: &encoder)
        try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec.writeComponent(
            payload.component,
            to: &encoder
        )
        return encoder.encodedBytes
    }

    static func decodeAnonymousComponent(
        from encodedBytes: [UInt8]
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha.AnonymousComponentPayload {
        try OpalFusion.Mosaic.CanonicalDecoder.decode(from: encodedBytes) { decoder in
            try .init(
                roundIdentifier: decoder.readFixedBytes(byteCount: 32),
                authorizationToken: readAuthorizationToken(from: &decoder),
                component: OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                    .readComponent(from: &decoder)
            )
        }
    }
}
