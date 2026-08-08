// OpalFusion+Mosaic+LocalAttempt+TranscriptInclusionValidation.swift

extension OpalFusion.Mosaic.LocalAttempt {
    /// A future protocol driver validates the local contributor's complete expected material.
    ///
    /// The validator must resolve the material identifier to locally owned commitments, openings,
    /// and components; require the complete expected local material exactly once in the prepared
    /// sets; and validate every applicable commitment opening and linkage. Those algorithms are not
    /// yet frozen by the Opal-v0 profile. Successful construction seals that validation to one
    /// attempt, generation, contributor, material identifier, and exact prepared transcript.
    protocol TranscriptInclusionValidating: Sendable {
        func validateCompleteInclusion(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        ) throws
    }

    struct TranscriptInclusionValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case inclusionRejected
        }

        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
        let materialIdentifier: MaterialIdentifier
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript

        init(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            materialIdentifier: MaterialIdentifier,
            transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript,
            using validator: some TranscriptInclusionValidating
        ) throws(ValidationError) {
            do {
                try validator.validateCompleteInclusion(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    contributor: contributor,
                    materialIdentifier: materialIdentifier,
                    transcript: transcript
                )
            } catch {
                throw .inclusionRejected
            }

            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.contributor = contributor
            self.materialIdentifier = materialIdentifier
            self.transcript = transcript
        }
    }
}
