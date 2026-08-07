// OpalFusion+Mosaic+RuntimeSession+AuthenticatedMessage.swift

extension OpalFusion.Mosaic.RuntimeSession {
    struct MessageIdentifier: Sendable, Hashable {
        enum ValidationError: Swift.Error, Sendable, Equatable {
            case invalidByteCount(actual: Int)
        }

        let bytes: [UInt8]

        init(bytes: [UInt8]) throws {
            guard bytes.count == 32 else {
                throw ValidationError.invalidByteCount(actual: bytes.count)
            }
            self.bytes = bytes
        }
    }

    /// A signed control message after cryptographic and canonical validation.
    struct AuthenticatedMessage: Sendable, Equatable {
        let attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
        let generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
        let sender: OpalFusion.Mosaic.Attempt.ControlIdentity
        let sequence: UInt64
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let messageIdentifier: MessageIdentifier
        let authenticatedFact: AuthenticatedFact

        init(
            attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
            generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
            sender: OpalFusion.Mosaic.Attempt.ControlIdentity,
            sequence: UInt64,
            phase: OpalFusion.Mosaic.Attempt.Phase,
            messageIdentifier: MessageIdentifier,
            authenticatedFact: AuthenticatedFact
        ) {
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.sender = sender
            self.sequence = sequence
            self.phase = phase
            self.messageIdentifier = messageIdentifier
            self.authenticatedFact = authenticatedFact
        }

        var localInput: OpalFusion.Mosaic.LocalAttempt.Input {
            .init(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                validatedFact: authenticatedFact.attemptInput
            )
        }
    }
}
