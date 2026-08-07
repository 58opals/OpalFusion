// OpalFusion+Mosaic+AnonymousReplayIndex.swift

extension OpalFusion.Mosaic {
    /// Idempotence guard for an already-authorized anonymous mailbox token.
    ///
    /// Blind authorization and token parsing stay in a future reviewed crypto
    /// adapter. This type only prevents one validated authorization from being
    /// used for two different authenticated payloads inside an attempt.
    struct AnonymousReplayIndex: Sendable {
        struct AuthorizationIdentifier: Sendable, Hashable {
            let validatedBytes: [UInt8]

            init(validatedBytes: [UInt8]) {
                self.validatedBytes = validatedBytes
            }
        }

        enum Decision: Sendable, Equatable {
            case accepted
            case duplicate
            case conflict
        }

        private var acceptedMessages: [
            AuthorizationIdentifier: RuntimeSession.MessageIdentifier
        ] = [:]

        mutating func record(
            authorization: AuthorizationIdentifier,
            messageIdentifier: RuntimeSession.MessageIdentifier
        ) -> Decision {
            if let acceptedMessage = acceptedMessages[authorization] {
                return acceptedMessage == messageIdentifier
                    ? .duplicate
                    : .conflict
            }
            acceptedMessages[authorization] = messageIdentifier
            return .accepted
        }
    }
}
