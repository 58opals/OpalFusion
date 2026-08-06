// OpalFusion+Mosaic+LocalAttempt+Input.swift

extension OpalFusion.Mosaic.LocalAttempt {
    /// One already-validated aggregate semantic fact routed to a peer-local attempt generation.
    struct Input: Sendable, Equatable {
        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let validatedFact: OpalFusion.Mosaic.Attempt.Input

        init(
            attemptIdentifier: AttemptIdentifier,
            generationIdentifier: GenerationIdentifier,
            validatedFact: OpalFusion.Mosaic.Attempt.Input
        ) {
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.validatedFact = validatedFact
        }
    }
}
