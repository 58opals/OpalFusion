// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRuntimeDriver+Model.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum InputSourceTermination: Sendable, Equatable {
        case finished
        case failed
    }
}

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRuntimeDriver {
    typealias Session = OpalFusion.Mosaic.OpalMainnetAlpha.RuntimeSession
    typealias Ledger = OpalFusion.Mosaic.OpalMainnetAlpha.AdmissionLedger
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport
    typealias AdmissionJournal = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestAdmissionJournal
    typealias InputSourceTermination = OpalFusion.Mosaic.OpalMainnetAlpha
        .InputSourceTermination

    struct Bootstrap: Sendable {
        let validatedAttempt: OpalFusion.Mosaic.Attempt
        let attemptIdentifier: Session.AttemptIdentifier
        let generationIdentifier: Session.GenerationIdentifier
        let materialIdentifier: Session.MaterialIdentifier
        let localControlIdentity: Session.ControlIdentity
        let proposalValidation: OpalFusion.Mosaic.OpalMainnetAlpha
            .ManifestProposalValidation

        init(
            validatedAttempt: OpalFusion.Mosaic.Attempt,
            attemptIdentifier: Session.AttemptIdentifier,
            generationIdentifier: Session.GenerationIdentifier,
            materialIdentifier: Session.MaterialIdentifier,
            localControlIdentity: Session.ControlIdentity,
            proposalValidation: OpalFusion.Mosaic.OpalMainnetAlpha
                .ManifestProposalValidation
        ) {
            self.validatedAttempt = validatedAttempt
            self.attemptIdentifier = attemptIdentifier
            self.generationIdentifier = generationIdentifier
            self.materialIdentifier = materialIdentifier
            self.localControlIdentity = localControlIdentity
            self.proposalValidation = proposalValidation
        }
    }

    struct ContributorDependencies: Sendable {
        let execution: OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator
            .ExecutionDependencies
        let expectedReservationExpiration: Date
        let maximumPendingInputCount: Int
        let makeReservationRequest: @Sendable (
            OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator
                .ReservationEligibility
        ) async throws -> OpalFusion.Host.MosaicReservationRequest
        let runtimeEffectObserver: @Sendable (Session.Effect) -> Void

        init(
            execution: OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator
                .ExecutionDependencies,
            expectedReservationExpiration: Date,
            maximumPendingInputCount: Int,
            makeReservationRequest: @escaping @Sendable (
                OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator
                    .ReservationEligibility
            ) async throws -> OpalFusion.Host.MosaicReservationRequest,
            runtimeEffectObserver: @escaping @Sendable (
                Session.Effect
            ) -> Void = { _ in }
        ) {
            self.execution = execution
            self.expectedReservationExpiration = expectedReservationExpiration
            self.maximumPendingInputCount = maximumPendingInputCount
            self.makeReservationRequest = makeReservationRequest
            self.runtimeEffectObserver = runtimeEffectObserver
        }

        var coordinatorDependencies: OpalFusion.Mosaic.OpalMainnetAlpha
            .ReservationCoordinator.Dependencies {
            .init(
                execution: execution,
                maximumPendingInputCount: maximumPendingInputCount,
                expectedReservationExpiration: expectedReservationExpiration,
                makeReservationRequest: makeReservationRequest,
                runtimeEffectObserver: runtimeEffectObserver
            )
        }
    }

    enum RoleDependencies: Sendable {
        case contributor(ContributorDependencies)
        case conductor(
            OpalFusion.Mosaic.OpalMainnetAlpha.ConductorCoordinator.Dependencies
        )

        var role: OpalFusion.Mosaic.Role {
            switch self {
            case .contributor:
                .contributor
            case .conductor:
                .conductor
            }
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case runtimeConstructionFailed
        case invalidInputBufferLimit
        case dependencyRoleMismatch(
            expected: OpalFusion.Mosaic.Role,
            received: OpalFusion.Mosaic.Role
        )
    }

    enum State: Sendable, Equatable {
        case contributor(
            OpalFusion.Mosaic.OpalMainnetAlpha.ReservationCoordinator.State
        )
        case conductor(
            OpalFusion.Mosaic.OpalMainnetAlpha.ConductorCoordinator.State
        )
    }
}
