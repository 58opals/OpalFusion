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
        case duplicateControlIdentity(ControlIdentity)
        case selectedRolesDoNotMatchControlRoster
        case manifestAgreementNotUnanimous
        case manifestDisagreement
        case conductorUsedContributorInput(during: Phase)
        case contributorSetMismatch(during: Phase)
        case transcriptAgreementNotUnanimous
        case transcriptRootDisagreement
        case invalidTransition(from: Phase, received: Input.Kind)
        case aborted(during: Phase, reason: AbortReason)
        case inPlaceRetryNotPermitted
        case inputAfterTermination
    }
}
