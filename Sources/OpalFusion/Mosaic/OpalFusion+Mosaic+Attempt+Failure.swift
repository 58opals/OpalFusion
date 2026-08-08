// OpalFusion+Mosaic+Attempt+Failure.swift

extension OpalFusion.Mosaic.Attempt {
    enum AbortReason: Sendable, Equatable {
        case timeout
        case equivocation
        case invalidAuthenticatedMessage
        case missingRequiredParticipant
    }

    enum Failure: Error, Sendable, Equatable {
        case invalidCandidateCount(actual: Int)
        case controlIdentityCountMismatch(expected: Int, actual: Int)
        case invalidRoleCommitmentSet(RoleCommitmentSet.ValidationError)
        case invalidRoleElectionValidation(RoleElectionResult.ValidationError)
        case invalidManifestAgreement(ManifestAgreement.ValidationError)
        case invalidCommitmentSet(CommitmentSetValidation.ValidationError)
        case invalidUnsignedTransactionTranscript(
            OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript.ValidationError
        )
        case conductorUsedContributorInput(during: Phase)
        case contributorSetMismatch(during: Phase)
        case transcriptAgreementNotUnanimous
        case transcriptAcknowledgementProfileMismatch
        case transcriptRoundIdentifierMismatch
        case transcriptRootDisagreement
        case transcriptRootMismatch(
            expected: TranscriptRoot,
            received: TranscriptRoot
        )
        case transcriptInclusionNotValidated
        case invalidTranscriptInclusionValidation
        case invalidTransition(from: Phase, received: Input.Kind)
        case aborted(during: Phase, reason: AbortReason)
        case inPlaceRetryNotPermitted
        case inputAfterTermination
    }
}
