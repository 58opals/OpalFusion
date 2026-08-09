// OpalFusion+Mosaic+OpalMainnetAlpha+ReservationCoordinator+Model.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator {
    typealias Session = OpalFusion.Mosaic.OpalMainnetAlpha.RuntimeSession

    struct ReservationEligibility: Sendable, Equatable {
        let context: Session.Context
        let manifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
    }

    struct Dependencies: Sendable {
        let transactionHost: any OpalFusion.Host.MosaicTransactionHost
        /// Caller-owned exact expiry until the profile freezes its manifest-deadline mapping.
        let expectedReservationExpiration: Date
        let makeReservationRequest: @Sendable (
            ReservationEligibility
        ) async throws -> OpalFusion.Host.MosaicReservationRequest
        let validateAndPublishReservedContribution: @Sendable (
            ReservationEligibility,
            OpalFusion.Host.MosaicReservationLease
        ) async throws -> Session.ReservationPublicationValidation
        /// Observes ordered raw runtime effects before coordinator-owned host disposition.
        ///
        /// Observing `sessionTerminated` does not mean coordinator termination has completed;
        /// callers must use `waitForTermination()` and inspect `state` for that boundary.
        let runtimeEffectObserver: @Sendable (Session.Effect) -> Void

        init(
            transactionHost: any OpalFusion.Host.MosaicTransactionHost,
            expectedReservationExpiration: Date,
            makeReservationRequest: @escaping @Sendable (
                ReservationEligibility
            ) async throws -> OpalFusion.Host.MosaicReservationRequest,
            validateAndPublishReservedContribution: @escaping @Sendable (
                ReservationEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> Session.ReservationPublicationValidation,
            runtimeEffectObserver: @escaping @Sendable (Session.Effect) -> Void = { _ in }
        ) {
            self.transactionHost = transactionHost
            self.expectedReservationExpiration = expectedReservationExpiration
            self.makeReservationRequest = makeReservationRequest
            self.validateAndPublishReservedContribution =
                validateAndPublishReservedContribution
            self.runtimeEffectObserver = runtimeEffectObserver
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case runtimeSessionNotFresh
        case localPeerIsNotContributor
    }

    enum State: Sendable, Equatable {
        case idle
        case running
        case stopping
        case terminal(Outcome)
        case recoveryRequired(Recovery)
    }

    enum Outcome: Sendable, Equatable {
        case failed(Failure)
        case cancelled(during: OpalFusion.Mosaic.Attempt.Phase)
    }

    enum Failure: Error, Sendable, Equatable {
        case missingManifest
        case effectContextMismatch
        case duplicateReservationEligibility
        case invalidReservationRequest
        case reservationFailed
        case reservationPublicationFailed
        case reservationPublicationLeaseMismatch
        case runtime(Session.Failure)
    }

    struct Recovery: Sendable, Equatable {
        enum Reason: Sendable, Equatable {
            case reservationReleaseFailed
        }

        let reservationReference: OpalFusion.Host.MosaicReservationReference
        let reason: Reason
    }

    enum ReservationLifecycle: Sendable, Equatable {
        case unreserved
        case reservationInFlight
        case reserved(OpalFusion.Host.MosaicReservationLease)
        case released(OpalFusion.Host.MosaicReservationReference)
        case releaseFailed(OpalFusion.Host.MosaicReservationReference)
    }
}
