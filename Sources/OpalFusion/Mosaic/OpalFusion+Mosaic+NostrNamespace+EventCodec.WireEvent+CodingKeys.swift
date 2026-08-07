// OpalFusion+Mosaic+NostrNamespace+EventCodec.WireEvent+CodingKeys.swift

extension OpalFusion.Mosaic.NostrNamespace.EventCodec.WireEvent {
    enum CodingKeys: String, CodingKey {
        case id, pubkey, kind, tags, content, sig
        case createdAt = "created_at"
    }
}
