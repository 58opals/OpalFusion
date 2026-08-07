// OpalFusion+Mosaic+RuntimeSession+HostResult.swift

extension OpalFusion.Mosaic.RuntimeSession {
    /// An aggregate fact produced only after the engine validates a wallet-host result.
    enum HostResult: Sendable, Equatable {
        case walletReservationsPrepared(
            contributors: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )
        case signedTransactionValidated(
            contributorSigners: [OpalFusion.Mosaic.Attempt.ControlIdentity]
        )

        var attemptInput: OpalFusion.Mosaic.Attempt.Input {
            switch self {
            case let .walletReservationsPrepared(contributors):
                .walletReservationsPrepared(contributors: contributors)
            case let .signedTransactionValidated(contributorSigners):
                .signedTransactionValidated(
                    contributorSigners: contributorSigners
                )
            }
        }
    }
}
