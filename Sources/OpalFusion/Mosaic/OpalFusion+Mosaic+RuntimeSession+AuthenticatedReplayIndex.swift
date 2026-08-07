// OpalFusion+Mosaic+RuntimeSession+AuthenticatedReplayIndex.swift

extension OpalFusion.Mosaic.RuntimeSession {
    struct AuthenticatedReplayIndex: Sendable {
        enum Decision: Sendable, Equatable {
            case accepted
            case duplicate
            case stale(greatestAcceptedSequence: UInt64)
            case conflict
        }

        private struct SequenceKey: Sendable, Hashable {
            let sender: OpalFusion.Mosaic.Attempt.ControlIdentity
            let sequence: UInt64
        }

        private var acceptedIdentifiers: [SequenceKey: MessageIdentifier] = [:]
        private var greatestSequences: [
            OpalFusion.Mosaic.Attempt.ControlIdentity: UInt64
        ] = [:]

        func containsExactDuplicate(_ message: AuthenticatedMessage) -> Bool {
            acceptedIdentifiers[
                SequenceKey(sender: message.sender, sequence: message.sequence)
            ] == message.messageIdentifier
        }

        mutating func record(_ message: AuthenticatedMessage) -> Decision {
            let key = SequenceKey(
                sender: message.sender,
                sequence: message.sequence
            )
            if let acceptedIdentifier = acceptedIdentifiers[key] {
                return acceptedIdentifier == message.messageIdentifier
                    ? .duplicate
                    : .conflict
            }
            if let greatestSequence = greatestSequences[message.sender],
               message.sequence < greatestSequence {
                return .stale(greatestAcceptedSequence: greatestSequence)
            }

            acceptedIdentifiers[key] = message.messageIdentifier
            greatestSequences[message.sender] = message.sequence
            return .accepted
        }
    }
}
