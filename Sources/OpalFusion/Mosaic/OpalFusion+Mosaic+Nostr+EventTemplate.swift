// OpalFusion+Mosaic+Nostr+EventTemplate.swift

extension OpalFusion.Mosaic.Nostr {
    struct EventTemplate: Sendable, Equatable {
        let createdAt: UInt64
        let kind: UInt16
        let tags: [[String]]
        let content: String

        init(
            createdAt: UInt64,
            kind: UInt16,
            tags: [[String]],
            content: String,
            limits: EventCodingLimits
        ) throws {
            try EventCodec.validate(
                tags: tags,
                content: content,
                limits: limits
            )
            self.createdAt = createdAt
            self.kind = kind
            self.tags = tags
            self.content = content
        }
    }
}
