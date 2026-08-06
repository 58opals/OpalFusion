// OpalFusion+Mosaic+LocalAttempt+Failure.swift

extension OpalFusion.Mosaic.LocalAttempt {
    enum Failure: Error, Sendable, Equatable {
        case attemptNotReadyForLocalBinding
        case localControlIdentityNotInRoster(OpalFusion.Mosaic.Attempt.ControlIdentity)
        case attemptIdentifierMismatch(
            expected: AttemptIdentifier,
            received: AttemptIdentifier
        )
        case generationIdentifierMismatch(
            expected: GenerationIdentifier,
            received: GenerationIdentifier
        )
        case attemptFailure(OpalFusion.Mosaic.Attempt.Failure)
    }
}
