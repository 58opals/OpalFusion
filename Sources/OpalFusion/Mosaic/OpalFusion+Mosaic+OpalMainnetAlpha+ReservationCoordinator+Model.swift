// OpalFusion+Mosaic+OpalMainnetAlpha+ReservationCoordinator+Model.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator {
    typealias Session = OpalFusion.Mosaic.OpalMainnetAlpha.RuntimeSession

    struct ReservationEligibility: Sendable, Equatable {
        let context: Session.Context
        let manifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
    }

    struct Dependencies: Sendable {
        struct ReservationOnly: Sendable {
            let transactionHost: any OpalFusion.Host.MosaicTransactionHost
            let validateAndPublishReservedContribution: @Sendable (
                ReservationEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> Session.ReservationPublicationValidation
        }

        enum Mode: Sendable {
            case reservationOnly(ReservationOnly)
            case contributorExecution(ExecutionDependencies)
        }

        let mode: Mode
        /// Caller-owned exact expiry until the profile freezes its manifest-deadline mapping.
        let expectedReservationExpiration: Date
        let makeReservationRequest: @Sendable (
            ReservationEligibility
        ) async throws -> OpalFusion.Host.MosaicReservationRequest
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
            mode = .reservationOnly(
                .init(
                    transactionHost: transactionHost,
                    validateAndPublishReservedContribution:
                        validateAndPublishReservedContribution
                )
            )
            self.expectedReservationExpiration = expectedReservationExpiration
            self.makeReservationRequest = makeReservationRequest
            self.runtimeEffectObserver = runtimeEffectObserver
        }

        init(
            execution: ExecutionDependencies,
            expectedReservationExpiration: Date,
            makeReservationRequest: @escaping @Sendable (
                ReservationEligibility
            ) async throws -> OpalFusion.Host.MosaicReservationRequest,
            runtimeEffectObserver: @escaping @Sendable (
                Session.Effect
            ) -> Void = { _ in }
        ) {
            mode = .contributorExecution(execution)
            self.expectedReservationExpiration = expectedReservationExpiration
            self.makeReservationRequest = makeReservationRequest
            self.runtimeEffectObserver = runtimeEffectObserver
        }

        var execution: ExecutionDependencies? {
            guard case let .contributorExecution(execution) = mode else {
                return nil
            }
            return execution
        }

        var transactionHost: any OpalFusion.Host.MosaicTransactionHost {
            switch mode {
            case let .reservationOnly(dependencies):
                dependencies.transactionHost
            case let .contributorExecution(dependencies):
                dependencies.transactionHost
            }
        }

        var reservationOnly: ReservationOnly? {
            guard case let .reservationOnly(dependencies) = mode else {
                return nil
            }
            return dependencies
        }
    }

    /// Additional authorities required to execute the reservation through exact host commit.
    struct LocalAnonymousComponentPublication: Sendable, Equatable {
        let slot: Int
        let recipientEventIdentity: [UInt8]
        let payload: OpalFusion.Mosaic.OpalMainnetAlpha.AnonymousComponentPayload
    }

    struct ExecutionDependencies: Sendable {
        let transactionHost: any OpalFusion.Host.MosaicCompleteTransactionHost
        let previousOutputSource: any OpalFusion.Host.MosaicPreviousOutputSource
        let makeLocalContributionMaterial: @Sendable (
            ReservationEligibility,
            OpalFusion.Host.MosaicReservationLease
        ) async throws -> OpalFusion.Mosaic.OpalMainnetAlpha
            .LocalContributionMaterial
        let publishPlayerCommit: @Sendable (
            OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit
        ) async throws -> Void
        let publishAnonymousComponents: @Sendable (
            [LocalAnonymousComponentPublication]
        ) async throws -> Void
        let publishPreSignAcknowledgement: @Sendable (
            OpalFusion.Mosaic.Attempt.ControlIdentity,
            [UInt8],
            OpalFusion.Mosaic.Attempt.TranscriptRoot
        ) async throws -> Void
        let publishLocalBCHSignatures: @Sendable (
            [OpalFusion.Mosaic.OpalMainnetAlpha.LocalBCHSignaturePublication]
        ) async throws -> Void

        init(
            transactionHost: any OpalFusion.Host.MosaicCompleteTransactionHost,
            previousOutputSource: any OpalFusion.Host.MosaicPreviousOutputSource,
            makeLocalContributionMaterial: @escaping @Sendable (
                ReservationEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> OpalFusion.Mosaic.OpalMainnetAlpha
                .LocalContributionMaterial,
            publishPlayerCommit: @escaping @Sendable (
                OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit
            ) async throws -> Void,
            publishAnonymousComponents: @escaping @Sendable (
                [LocalAnonymousComponentPublication]
            ) async throws -> Void,
            publishPreSignAcknowledgement: @escaping @Sendable (
                OpalFusion.Mosaic.Attempt.ControlIdentity,
                [UInt8],
                OpalFusion.Mosaic.Attempt.TranscriptRoot
            ) async throws -> Void,
            publishLocalBCHSignatures: @escaping @Sendable (
                [OpalFusion.Mosaic.OpalMainnetAlpha
                    .LocalBCHSignaturePublication]
            ) async throws -> Void
        ) {
            self.transactionHost = transactionHost
            self.previousOutputSource = previousOutputSource
            self.makeLocalContributionMaterial = makeLocalContributionMaterial
            self.publishPlayerCommit = publishPlayerCommit
            self.publishAnonymousComponents = publishAnonymousComponents
            self.publishPreSignAcknowledgement = publishPreSignAcknowledgement
            self.publishLocalBCHSignatures = publishLocalBCHSignatures
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
        case completed
        case failed(Failure)
        case cancelled(during: OpalFusion.Mosaic.Attempt.Phase)
    }

    enum Failure: Error, Sendable, Equatable {
        case missingManifest
        case effectContextMismatch
        case duplicateReservationEligibility
        case invalidReservationRequest
        case reservationFailed
        case reservationLeaseExpirationMismatch
        case reservationPublicationFailed
        case reservationPublicationLeaseMismatch
        case localMaterialInvalid
        case authorizationResponseValidationFailed
        case commitmentInclusionValidationFailed
        case anonymousComponentPublicationFailed
        case transcriptInclusionValidationFailed
        case preSignAcknowledgementPublicationFailed
        case signingPrerequisiteMissing
        case previousOutputResolutionFailed
        case signingRequestFailed
        case signingFailed
        case localBCHSignatureValidationFailed
        case localBCHSignaturePublicationFailed
        case completeTransactionValidationFailed
        case completeTransactionCommitFailed
        case localAttemptRejected(OpalFusion.Mosaic.LocalAttempt.Failure)
        case runtime(Session.Failure)
    }

    struct Recovery: Sendable, Equatable {
        enum Reason: Sendable, Equatable {
            case reservationReleaseFailed
            case unexpectedRuntimeCompletion
            case signingMayHaveStarted
            case signingFailed
            case localBCHSignatureValidationFailed
            case localBCHSignaturePublicationFailed
            case completeTransactionValidationFailed
            case completeTransactionCommitFailed
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
        case releaseFailed(OpalFusion.Host.MosaicReservationReference)
    }
}
