// OpalFusion+Mosaic+OpalMainnetAlpha+ContractError.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    enum ContractError: Error, Sendable, Equatable {
        case unsupportedProfile(OpalFusion.Mosaic.Profile)
        case invalidFixedByteCount(field: Field, expected: Int, actual: Int)
        case profileMismatch
        case networkMismatch
        case transportProfileMismatch
        case transactionProfileMismatch
        case invalidRole(UInt8)
        case invalidPhase(UInt8)
        case rosterMismatch
        case duplicateControlIdentity
        case nonCanonicalRosterOrder
        case invalidComponentCount(actual: Int)
        case invalidFeeTerms
        case invalidDeadlineOrder
        case invalidBlindSigningKey
        case invalidManifestSignatureCount(expected: Int, actual: Int)
        case unknownManifestSigner
        case duplicateManifestSigner
        case nonCanonicalManifestSignatureOrder
        case invalidManifestSignature
        case roleCommitmentMismatch
        case candidateSetDigestMismatch
        case poolIdentifierMismatch
        case invalidAuthorizationRequestCount(actual: Int)
        case invalidAuthorizationRequestSlot(expected: Int, actual: Int)
        case groupedCommitmentProfileMismatch(OpalFusion.Mosaic.Profile)
        case invalidAuthorizationResponseCount(actual: Int)
        case invalidAuthorizationResponseSlot(expected: Int, actual: Int)
        case invalidPreSignAcknowledgementCount(expected: Int, actual: Int)
        case invalidPreSignAcknowledgementContributor
        case invalidAggregateByteCount(actual: Int)
        case invalidAggregateFragmentCount(expected: Int, actual: Int)
        case invalidAggregateFragmentIndex(index: Int, count: Int)
        case invalidAggregateFragmentBodyCount(expected: Int, actual: Int)
        case aggregateDecodingContextMismatch(AggregateKind)
        case invalidCanonicalAggregate(AggregateKind)
        case sequenceOverflow
        case payloadTooLarge(maximum: Int, actual: Int)
        case payloadDigestMismatch
        case invalidControlIdentity
        case invalidEventIdentity
        case reusedControlAndEventIdentity
        case invalidControlSignature
        case outerEventIdentityMismatch
        case recipientEventIdentityMismatch
        case expiredEnvelope(expiryUnixSeconds: UInt64, currentUnixSeconds: UInt64)
        case invalidCommunicationPublicKey
        case communicationEventIdentityMismatch
        case invalidPayloadPhase
        case aggregatePublisherMismatch
        case aggregateRoundMismatch
        case aggregateTranscriptMismatch
        case missingAggregateReservation
        case unsupportedAnonymousPayloadType(AnonymousPayloadType)
        case invalidAuthorizationToken
        case anonymousComponentRoundMismatch
        case anonymousComponentAdmissionRejected
        case invalidBCHSignature
        case invalidBCHPublicKey
        case invalidSignatureSetCount(expected: Int, actual: Int)
        case invalidSignatureInputIndex(expected: Int, actual: Int)
        case duplicateSignatureInputIndex(UInt32)
        case nonCanonicalSignatureOrder
        case transcriptMismatch
        case transactionMismatch
        case missingCompleteTransactionTranscript
        case invalidCompleteTransaction
        case invalidSpentInput(index: Int)
        case invalidP2PKHLockingScript(index: Int)
        case bchSignatureVerificationFailed(index: Int)

        enum Field: String, Sendable, Equatable {
            case candidateSetDigest
            case controlRosterDigest
            case roleSeed
            case controlIdentity
            case poolIdentifier
            case nonceAllocationDigest
            case relaySetDigest
            case roundIdentifier
            case manifestDigest
            case playerCommitDigest
            case transcriptRoot
            case aggregateDigest
            case payloadDigest
            case senderEventIdentity
            case recipientEventIdentity
            case controlSignature
            case bchSignature
            case bchPublicKey
        }
    }
}
