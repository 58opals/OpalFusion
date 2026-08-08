// OpalFusion+Mosaic+LocalAttempt+Input.swift

extension OpalFusion.Mosaic.LocalAttempt {
    /// One attempt-bound aggregate fact or contributor-local validation.
    struct Input: Sendable, Equatable {
        enum Payload: Sendable, Equatable {
            case aggregate(OpalFusion.Mosaic.Attempt.Input)
            case transcriptInclusion(TranscriptInclusionValidation)
        }

        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let payload: Payload

        init(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            attemptInput: OpalFusion.Mosaic.Attempt.Input
        ) {
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.payload = .aggregate(attemptInput)
        }

        init(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            validatedTranscriptInclusion: TranscriptInclusionValidation
        ) {
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.payload = .transcriptInclusion(validatedTranscriptInclusion)
        }
    }
}
