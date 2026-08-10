// OpalFusion+Mosaic+OpalMainnetAlpha+AdmissionLedger+Model.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha.AdmissionLedger {
    typealias AttemptIdentifier = OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier
    typealias GenerationIdentifier = OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier
    typealias MaterialIdentifier = OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    typealias ControlIdentity = OpalFusion.Mosaic.Attempt.ControlIdentity
    typealias Transcript = OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
    typealias ContractError = OpalFusion.Mosaic.OpalMainnetAlpha.ContractError

    enum InitializationError: Error, Sendable, Equatable {
        case localControlIdentityNotInRoster(ControlIdentity)
    }

    enum PhaseContext: Sendable, Equatable {
        case manifestAgreement
        case walletReservation
        case groupedCommitment
        case anonymousComponentSubmission
        case transcriptAgreement(Transcript)
        case bchSigning(Transcript)

        var phase: OpalFusion.Mosaic.Attempt.Phase {
            switch self {
            case .manifestAgreement:
                .manifestAgreement
            case .walletReservation:
                .walletReservation
            case .groupedCommitment:
                .groupedCommitment
            case .anonymousComponentSubmission:
                .anonymousComponentSubmission
            case .transcriptAgreement:
                .transcriptAgreement
            case .bchSigning:
                .bchSigning
            }
        }

        var transcript: Transcript? {
            switch self {
            case let .transcriptAgreement(transcript),
                 let .bchSigning(transcript):
                transcript
            case .manifestAgreement, .walletReservation, .groupedCommitment,
                 .anonymousComponentSubmission:
                nil
            }
        }
    }

    enum DocumentSlot: Sendable, Equatable {
        case completeManifest
        case playerCommit(ControlIdentity)
        case authorizationResponseSet(ControlIdentity)
        case commitmentSet
        case componentSet
        case preSignAcknowledgement(ControlIdentity)
        case preSignAcknowledgementSet
        case bchSignatureSet
        case completeTransaction
    }

    enum Failure: Error, Sendable, Equatable {
        case attemptIdentifierMismatch
        case generationIdentifierMismatch
        case materialIdentifierMismatch
        case foreignRound
        case senderNotInRoster
        case outerEventIdentityMismatch
        case expiredEnvelope
        case sequenceGap(expected: UInt64, received: UInt64)
        case sequenceConflict(sender: ControlIdentity, sequence: UInt64)
        case sequenceExhausted(sender: ControlIdentity)
        case invalidControlEnvelope(ContractError)
        case aggregateInterleaving(sender: ControlIdentity)
        case aggregateReassemblyFailed(ContractError)
        case activeAggregateRunPreventsPhaseAdvance
        case invalidPhaseTransition(
            from: OpalFusion.Mosaic.Attempt.Phase,
            to: OpalFusion.Mosaic.Attempt.Phase
        )
        case phaseTransitionValidationMismatch
        case phaseAdvancePrerequisiteMissing(OpalFusion.Mosaic.Attempt.Phase)
        case conflictingDocument(DocumentSlot)
        case completeManifestCoreMismatch
        case playerCommitSetIncomplete
        case playerCommitSemanticValidationFailed(
            OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommitSemanticValidation
                .ValidationError
        )
        case commitmentSetInvalid(
            OpalFusion.Mosaic.Attempt.CommitmentSetValidation.ValidationError
        )
        case playerCommitAdmissionUnavailable
        case authorizationResponseSetPlayerCommitMismatch
        case authorizationResponseSetValidationMismatch
        case commitmentSetDoesNotMatchPlayerCommits
        case anonymousComponentAdmissionUnavailable
        case anonymousComponentAdmissionRejected(ContractError)
        case anonymousMessageConflict
        case anonymousAuthorizationConflict
        case anonymousCommunicationKeyReuse
        case anonymousRecipientIdentityReuse
        case anonymousComponentLimitExceeded
        case anonymousMailboxSequenceInvalid(expected: UInt64, actual: UInt64)
        case anonymousBCHSignatureAdmissionUnavailable
        case anonymousBCHSignatureAdmissionRejected(ContractError)
        case anonymousBCHSignatureInputConflict(UInt32)
        case anonymousBCHSignatureLimitExceeded
        case bchSignatureSetConstructionFailed
        case bchSignatureSetDoesNotMatchAnonymousAdmissions
        case completeTransactionPrerequisiteMissing
        case completeTransactionSignatureSetMismatch
        case completeTransactionValidationMismatch
        case completeTransactionValidationFailed(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .CompleteTransactionValidationRejection.Reason
        )
        case anonymousComponentSetIncomplete
        case componentSetDoesNotMatchAnonymousAdmissions
        case unsignedTransactionInvalid(
            OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript.ValidationError
        )
        case preSignAcknowledgementAdmissionUnavailable
        case transcriptAcknowledgementMismatch
        case preSignAcknowledgementSetDoesNotMatchCollection
        case unsupportedAnonymousBCHSignature
        case runtimeSessionBridgeMismatch
        case inPlaceRetryNotPermitted
        case inputAfterTermination
    }

    struct ControlDelivery: Sendable, Equatable {
        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let envelope: OpalFusion.Mosaic.OpalMainnetAlpha.ControlEnvelope
        let authenticatedOuterEventIdentity: [UInt8]
        let currentUnixSeconds: UInt64
    }

    struct AnonymousDelivery: Sendable, Equatable {
        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let envelope: OpalFusion.Mosaic.OpalMainnetAlpha.AnonymousEnvelope
        let authenticatedOuterEventIdentity: [UInt8]
        let authenticatedRecipientEventIdentity: [UInt8]
        let authenticatedMessageIdentifier: OpalFusion.Mosaic.RuntimeSession
            .MessageIdentifier
        let currentUnixSeconds: UInt64
    }

    struct PhaseTransitionRequest: Sendable, Equatable {
        let attemptIdentifier: AttemptIdentifier
        let generationIdentifier: GenerationIdentifier
        let from: PhaseContext
        let to: PhaseContext
    }

    struct AuthorizationResponseValidationDelivery: Sendable, Equatable {
        let validation: OpalFusion.Mosaic.OpalMainnetAlpha
            .AuthorizationResponseSetMaterialValidation
    }

    protocol PhaseTransitionValidating: Sendable {
        func validatePhaseTransition(_ request: PhaseTransitionRequest) throws
    }

    struct PhaseTransitionValidation: Sendable, Equatable {
        let request: PhaseTransitionRequest

        init<Validator>(
            validating request: PhaseTransitionRequest,
            using validator: Validator
        ) throws where Validator: PhaseTransitionValidating {
            try validator.validatePhaseTransition(request)
            self.request = request
        }
    }

    enum Input: Sendable, Equatable {
        case control(ControlDelivery)
        case authorizationResponseSetValidated(
            AuthorizationResponseValidationDelivery
        )
        case completeTransactionValidationFailed(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .CompleteTransactionValidationRejection
        )
        case cancel
        case retryRequested
    }

    enum Outcome: Sendable, Equatable {
        case completed
        case failed(Failure)
        case cancelled(during: OpalFusion.Mosaic.Attempt.Phase)
    }

    enum State: Sendable, Equatable {
        case active(PhaseContext)
        case terminal(Outcome)
    }

    enum Effect: Sendable, Equatable {
        case aggregateReservationAccepted(
            sender: ControlIdentity,
            kind: OpalFusion.Mosaic.OpalMainnetAlpha.AggregateKind,
            fragmentCount: Int
        )
        case aggregateFragmentAccepted(
            sender: ControlIdentity,
            received: Int,
            expected: Int
        )
        case exactDuplicateIgnored
        case manifestAdmitted(OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest)
        case playerCommitAdmitted(OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit)
        case playerCommitUnanimityReached(
            [OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit]
        )
        case authorizationResponseSetAdmitted(
            OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationResponseSet
        )
        case authorizationResponseSetValidationRequired(
            OpalFusion.Mosaic.OpalMainnetAlpha.AuthorizationResponseSet,
            playerCommit: OpalFusion.Mosaic.OpalMainnetAlpha.PlayerCommit
        )
        case authorizationResponsesValidated(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .AuthorizationResponseSetMaterialValidation
        )
        case commitmentSetAdmitted(OpalFusion.Mosaic.OpalV0.CommitmentSet)
        case componentSetAdmitted(
            OpalFusion.Mosaic.OpalV0.ComponentSet,
            transcript: Transcript
        )
        case anonymousComponentAdmitted(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .AnonymousComponentAdmissionValidation
        )
        case anonymousBCHSignatureAdmitted(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .AnonymousBCHSignatureAdmissionValidation
        )
        case bchSignatureSetReady(
            OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureSet
        )
        case bchSignatureSetAdmitted(
            OpalFusion.Mosaic.OpalMainnetAlpha.BCHSignatureSet
        )
        case completeTransactionAdmitted(
            OpalFusion.Mosaic.OpalMainnetAlpha.CompleteTransactionPayload
        )
        case completeTransactionValidationRequired(
            OpalFusion.Mosaic.OpalMainnetAlpha.CompleteTransactionCandidate
        )
        case completeTransactionValidated(
            OpalFusion.Mosaic.OpalMainnetAlpha.CompleteTransactionValidation
        )
        case preSignAcknowledgementAdmitted(
            OpalFusion.Mosaic.OpalMainnetAlpha
                .PreSignAcknowledgementSubmission
        )
        case preSignAcknowledgementCollectionComplete(
            [OpalFusion.Mosaic.OpalMainnetAlpha
                .PreSignAcknowledgementSubmission]
        )
        case preSignAcknowledgementSetAdmitted(
            OpalFusion.Mosaic.OpalMainnetAlpha.PreSignAcknowledgementSet
        )
        case phaseAdvanced(PhaseContext)
        case attemptTerminated(Outcome)
        case inputRejected(Failure)
    }
}
