// OpalFusion+Mosaic+OpalMainnetAlpha+RuntimeSession+Model.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.RuntimeSession {
    typealias Ledger = OpalFusion.Mosaic.OpalMainnetAlpha.AdmissionLedger
    typealias AttemptIdentifier = OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
    typealias GenerationIdentifier = OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
    typealias MaterialIdentifier = OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    typealias ControlIdentity = OpalFusion.Mosaic.Attempt.ControlIdentity

    struct Context: Sendable, Equatable {
        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let materialIdentifier: MaterialIdentifier
        let localControlIdentity: ControlIdentity
        let localRole: OpalFusion.Mosaic.Role
        let roster: OpalFusion.Mosaic.Attempt.Roster
        let proposalRoundIdentifier: [UInt8]
    }

    enum InitializationError: Error, Sendable, Equatable {
        case unsupportedProfile(OpalFusion.Mosaic.Profile)
        case attemptNotReady
        case proposalValidationMismatch
        case localAttemptBindingFailed
        case admissionLedgerBindingFailed
    }

    struct ReservationPublicationRequest: Sendable, Equatable {
        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let materialIdentifier: MaterialIdentifier
        let contributor: ControlIdentity
        let manifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
        let reservationLease: OpalFusion.Host.MosaicReservationLease
        let playerCommit: OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit

        var reservationReference: OpalFusion.Host.MosaicReservationReference {
            reservationLease.reference
        }
    }

    protocol ReservationPublicationValidating: Sendable {
        func validateReservationPublication(
            _ request: ReservationPublicationRequest
        ) throws
    }

    /// Records an externally validated reservation-publication binding.
    ///
    /// The bridge cannot mint this value. A later production material owner must verify that the
    /// reservation lease is live and that the exact `PlayerCommit` was derived from its
    /// attempt-, generation-, material-, manifest-, and contributor-bound contents.
    struct ReservationPublicationValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case rejected
        }

        let request: ReservationPublicationRequest

        init(
            validating request: ReservationPublicationRequest,
            using validator: some ReservationPublicationValidating
        ) throws(ValidationError) {
            do {
                try validator.validateReservationPublication(request)
            } catch {
                throw .rejected
            }
            self.request = request
        }
    }

    enum Input: Sendable, Equatable {
        case control(Ledger.ControlDelivery)
        case authorizationResponseSetValidated(
            Ledger.AuthorizationResponseValidationDelivery
        )
        case reservationPublicationValidated(
            ReservationPublicationValidation
        )
        case transcriptInclusionValidated(
            OpalFusion.Mosaic.LocalAttempt.TranscriptInclusionValidation
        )
        case completeTransactionValidated(
            OpalFusion.Mosaic.OpalMainnetAlpha.CompleteTransactionValidation
        )
        case completeTransactionValidationFailed(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .CompleteTransactionValidationRejection
        )
        case cancel
        case retryRequested
    }

    enum State: Sendable, Equatable {
        case active(OpalFusion.Mosaic.Attempt.Phase)
        case terminal(Outcome)
    }

    enum Outcome: Sendable, Equatable {
        case completed
        case failed(Failure)
        case cancelled(during: OpalFusion.Mosaic.Attempt.Phase)
    }

    enum Failure: Error, Sendable, Equatable {
        case admission(OpalFusion.Mosaic.OpalMainnetAlpha.AdmissionLedger.Failure)
        case localAttempt(OpalFusion.Mosaic.Attempt.Failure)
        case reservationPublicationUnavailable
        case reservationPublicationMismatch
        case localCommitmentSetMismatch
        case phaseSynchronizationFailed
        case transcriptMismatch
        case completeTransactionValidationUnavailable
        case completeTransactionValidationMismatch
        case completeTransactionValidationFailed(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .CompleteTransactionValidationRejection.Reason
        )
        case inPlaceRetryNotPermitted
        case inputAfterTermination
    }

    enum Effect: Sendable, Equatable {
        case admission(Ledger.Effect)
        case localAttempt(OpalFusion.Mosaic.LocalAttempt.Effect)
        case reservationPublicationAccepted(
            OpalFusion.Host.MosaicReservationReference
        )
        case exactDuplicateIgnored
        case sessionTerminated(Outcome)
        case inputRejected(Failure)
    }
}
