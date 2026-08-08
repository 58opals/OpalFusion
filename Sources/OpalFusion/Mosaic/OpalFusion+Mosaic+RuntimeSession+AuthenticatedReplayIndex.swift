// OpalFusion+Mosaic+RuntimeSession+AuthenticatedReplayIndex.swift

extension OpalFusion.Mosaic.RuntimeSession {
    struct AuthenticatedReplayIndex: Sendable {
        private var acceptedIdentifiers: [
            OpalFusion.Mosaic.Attempt.ControlIdentity: [UInt64: MessageIdentifier]
        ] = [:]
        private var greatestSequences: [
            OpalFusion.Mosaic.Attempt.ControlIdentity: UInt64
        ] = [:]

        func containsExactDuplicate(_ message: AuthenticatedMessage) -> Bool {
            acceptedIdentifiers[message.sender]?[message.sequence]
                == message.messageIdentifier
        }

        mutating func record(
            _ message: AuthenticatedMessage,
            profile: OpalFusion.Mosaic.Profile
        ) -> Decision {
            if let acceptedIdentifier = acceptedIdentifiers[message.sender]?[message.sequence] {
                return acceptedIdentifier == message.messageIdentifier
                    ? .duplicate
                    : .conflict
            }
            if profile.supportsExecutableCore {
                let expectedSequence = greatestSequences[message.sender].map {
                    $0 + 1
                } ?? 0
                guard message.sequence == expectedSequence else {
                    return .gap(
                        expectedSequence: expectedSequence,
                        receivedSequence: message.sequence
                    )
                }
            }
            if let greatestSequence = greatestSequences[message.sender],
               message.sequence < greatestSequence {
                return .stale(greatestAcceptedSequence: greatestSequence)
            }

            acceptedIdentifiers[message.sender, default: [:]][message.sequence]
                = message.messageIdentifier
            greatestSequences[message.sender] = message.sequence
            return .accepted
        }
    }
}
