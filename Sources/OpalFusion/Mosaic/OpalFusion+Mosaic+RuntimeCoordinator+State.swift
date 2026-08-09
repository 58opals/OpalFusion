// OpalFusion+Mosaic+RuntimeCoordinator+State.swift

extension OpalFusion.Mosaic.RuntimeCoordinator {
    enum State: Sendable, Equatable {
        case idle
        case running
        case stopping
        case terminal(Outcome)
        case recoveryRequired(Recovery)
    }

    enum Outcome: Sendable, Equatable {
        case completed
        case failed(Failure)
        case cancelled(
            OpalFusion.Mosaic.Attempt.Cancellation,
            inputSource: OpalFusion.Mosaic.RuntimeSessionDriver
                .InputSourceTermination?
        )
    }

    enum Failure: Error, Sendable, Equatable {
        case localPeerIsNotContributor
        case effectContextMismatch
        case duplicateReservationEligibility
        case reservationRequestFailed
        case reservationFailed
        case reservationPublicationFailed
        case transcriptInclusionValidationFailed
        case preSignPublicationFailed
        case missingReservation
        case signingRequestFailed
        case signingFailed
        case localSignaturePublicationFailed
        case completeTransactionUnavailable
        case completeTransactionCommitFailed
        case reservationReleaseFailed
        case localResultRejected(OpalFusion.Mosaic.LocalAttempt.Failure)
        case runtime(OpalFusion.Mosaic.Attempt.Failure)
        case driverEndedWithoutOutcome
        case completedWithoutCommittedReservation
    }

    struct Recovery: Sendable, Equatable {
        enum Reason: Sendable, Equatable {
            case cancellationAfterSigningMayHaveStarted
            case signingFailed
            case localSignaturePublicationFailed
            case completeTransactionUnavailable
            case completeTransactionCommitFailed
            case reservationReleaseFailed
            case reservationDispositionMissing
        }

        let reservationReference: OpalFusion.Host.MosaicReservationReference
        let reason: Reason
    }

    enum ReservationLifecycle: Sendable, Equatable {
        case unreserved
        case reservationInFlight
        case reserved(OpalFusion.Host.MosaicReservationLease)
        case signingMayHaveStarted(OpalFusion.Host.MosaicReservationLease)
        case locallySigned(
            OpalFusion.Host.MosaicReservationLease,
            OpalFusion.Host.FinalizedTransaction
        )
        case committed(OpalFusion.Host.MosaicReservationReference)
        case released(OpalFusion.Host.MosaicReservationReference)
    }
}
