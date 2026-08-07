// OpalFusion+Mosaic+RuntimeSession+Input.swift

extension OpalFusion.Mosaic.RuntimeSession {
    enum Input: Sendable, Equatable {
        case local(LocalOperation)
        case hostResult(HostResult)
        case authenticated(AuthenticatedMessage)
    }

    enum LocalOperation: Sendable, Equatable {
        case cancel
        case retryRequested

        var attemptInput: OpalFusion.Mosaic.Attempt.Input {
            switch self {
            case .cancel: .cancel
            case .retryRequested: .retryRequested
            }
        }
    }

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
