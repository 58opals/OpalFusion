// OpalFusion+Mosaic+OpalMainnetAlpha+ConductorCoordinator+Model.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.ConductorCoordinator {
    typealias Session = OpalFusion.Mosaic.OpalMainnetAlpha.RuntimeSession
    typealias Ledger = OpalFusion.Mosaic.OpalMainnetAlpha.AdmissionLedger

    struct Dependencies: Sendable {
        let componentAuthorizationEvaluator: OpalFusion.Mosaic.OpalV0
            .AuthorizationEvaluator
        let bchSignatureAuthorizationEvaluator: OpalFusion.Mosaic.OpalV0
            .AuthorizationEvaluator
        let previousOutputSource: any OpalFusion.Host.MosaicPreviousOutputSource
        let maximumPendingInputCount: Int
        /// Hands a typed document to the external publisher.
        ///
        /// This operation must return after publication acknowledgement. It must not wait for the
        /// document's semantic loopback admission or synchronously call back into the coordinator.
        let handoffPublication: @Sendable (
            PublicationValidation
        ) async throws -> Void

        init(
            componentAuthorizationEvaluator: OpalFusion.Mosaic.OpalV0
                .AuthorizationEvaluator,
            bchSignatureAuthorizationEvaluator: OpalFusion.Mosaic.OpalV0
                .AuthorizationEvaluator,
            previousOutputSource: any OpalFusion.Host.MosaicPreviousOutputSource,
            maximumPendingInputCount: Int,
            handoffPublication: @escaping @Sendable (
                PublicationValidation
            ) async throws -> Void
        ) {
            self.componentAuthorizationEvaluator =
                componentAuthorizationEvaluator
            self.bchSignatureAuthorizationEvaluator =
                bchSignatureAuthorizationEvaluator
            self.previousOutputSource = previousOutputSource
            self.maximumPendingInputCount = maximumPendingInputCount
            self.handoffPublication = handoffPublication
        }
    }

    enum Publication: Sendable, Equatable {
        case authorizationResponseSet(
            OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationResponseSet
        )
        case commitmentSet(OpalFusion.Mosaic.OpalV0.CommitmentSet)
        case componentSet(OpalFusion.Mosaic.OpalV0.ComponentSet)
        case preSignAcknowledgementSet(
            OpalFusion.Mosaic.OpalMainnetAlpha.PreSignAcknowledgementSet
        )
        case bchSignatureSet(
            OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureSet
        )
        case completeTransaction(
            OpalFusion.Mosaic.OpalMainnetAlpha.CompleteTransactionPayload
        )

        var kind: PublicationKind {
            switch self {
            case .authorizationResponseSet:
                .authorizationResponseSet
            case .commitmentSet:
                .commitmentSet
            case .componentSet:
                .componentSet
            case .preSignAcknowledgementSet:
                .preSignAcknowledgementSet
            case .bchSignatureSet:
                .bchSignatureSet
            case .completeTransaction:
                .completeTransaction
            }
        }
    }

    enum PublicationKind: Sendable, Equatable, Hashable {
        case authorizationResponseSet
        case commitmentSet
        case componentSet
        case preSignAcknowledgementSet
        case bchSignatureSet
        case completeTransaction
    }

    enum InitializationError: Error, Sendable, Equatable {
        case invalidInputBufferLimit
        case runtimeSessionNotFresh
        case localPeerIsNotConductor
    }

    enum State: Sendable, Equatable {
        case idle
        case running
        case stopping
        case terminal(Outcome)
    }

    enum Outcome: Sendable, Equatable {
        case completed
        case failed(Failure)
        case cancelled(during: OpalFusion.Mosaic.Attempt.Phase)
    }

    typealias InputSourceTermination = OpalFusion.Mosaic.OpalMainnetAlpha
        .InputSourceTermination

    enum Failure: Error, Sendable, Equatable {
        case inputBufferOverflow
        case inputSourceTerminated(InputSourceTermination)
        case recoveryBarrierMisordered
        case admissionJournalFailed
        case authorizationKeyMismatch
        case authorizationResponseSetMismatch
        case authorizationIssuanceFailed
        case authorizationResponseSetConstructionFailed
        case commitmentSetConstructionFailed
        case componentSetConstructionFailed
        case previousOutputResolutionFailed
        case preSignAcknowledgementSetConstructionFailed
        case bchSignatureAdmissionUnavailable
        case completeTransactionAssemblyFailed
        case completeTransactionValidationFailed
        case publicationFailed(PublicationKind)
        case unexpectedLocalAttemptEffect
        case runtime(Session.Failure)
    }
}
