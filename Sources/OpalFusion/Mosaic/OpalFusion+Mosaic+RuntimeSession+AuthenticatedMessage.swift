// OpalFusion+Mosaic+RuntimeSession+AuthenticatedMessage.swift

extension OpalFusion.Mosaic.RuntimeSession {
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

        func localInput(
            expectedManifestSignatureCount: Int,
            expectedTranscriptAcknowledgementCount: Int,
            transcriptAcknowledgementProfile: OpalFusion.Mosaic.Profile
        ) throws(OpalFusion.Mosaic.RuntimeSession.Failure)
            -> OpalFusion.Mosaic.LocalAttempt.Input {
            .init(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                attemptInput: try authenticatedFact.attemptInput(
                    expectedManifestSignatureCount:
                        expectedManifestSignatureCount,
                    expectedTranscriptAcknowledgementCount:
                        expectedTranscriptAcknowledgementCount,
                    transcriptAcknowledgementProfile:
                        transcriptAcknowledgementProfile
                )
            )
        }

        func terminalRejectionInput() -> OpalFusion.Mosaic.LocalAttempt.Input {
            .init(
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                attemptInput: .abort(.invalidAuthenticatedMessage)
            )
        }
    }
}
