// OpalFusion+Mosaic+NostrNamespace+EventCodec+WireEvent.swift

extension OpalFusion.Mosaic.NostrNamespace.EventCodec {
    struct WireEvent: Decodable {
        let id: String
        let pubkey: String
        let createdAt: UInt64
        let kind: UInt16
        let tags: [[String]]
        let content: String
        let sig: String
    }
}
