// OpalFusion+Client+Diagnostics+Event.swift

public extension OpalFusion.Client.Diagnostics {
    struct Event: Sendable, Equatable {
        public let kind: Kind
        public let summary: String
        public let messageKind: String?
        public let payloadByteCount: Int?
        public let retryAttempt: Int?
        public let retryDelayMilliseconds: Int?
        public let handshakeStage: OpalFusion.Client.Diagnostics.HandshakeStage

        public init(
            kind: Kind,
            summary: String,
            messageKind: String? = nil,
            payloadByteCount: Int? = nil,
            retryAttempt: Int? = nil,
            retryDelayMilliseconds: Int? = nil,
            handshakeStage: OpalFusion.Client.Diagnostics.HandshakeStage = .notStarted
        ) {
            self.kind = kind
            self.summary = summary
            self.messageKind = messageKind
            self.payloadByteCount = payloadByteCount
            self.retryAttempt = retryAttempt
            self.retryDelayMilliseconds = retryDelayMilliseconds
            self.handshakeStage = handshakeStage
        }
    }
}
