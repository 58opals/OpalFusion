// OpalFusion+Mosaic+RuntimeSession+HostResult.swift

extension OpalFusion.Mosaic.RuntimeSession {
    /// An aggregate fact produced only after the engine validates a wallet-host result.
    enum HostResult: Sendable, Equatable {
        case walletReservationsPrepared(
            attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
            generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
            contributors: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )
        case signedTransactionValidated(
            attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
            generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
            contributorSigners: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )

        var localInput: OpalFusion.Mosaic.LocalAttempt.Input {
            switch self {
            case let .walletReservationsPrepared(
                attemptIdentifier,
                generationIdentifier,
                contributors
            ):
                .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    attemptInput: .walletReservationsPrepared(
                        contributors: contributors
                    )
                )
            case let .signedTransactionValidated(
                attemptIdentifier,
                generationIdentifier,
                contributorSigners
            ):
                .init(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    attemptInput: .signedTransactionValidated(
                        contributorSigners: contributorSigners
                    )
                )
            }
        }
    }
}
