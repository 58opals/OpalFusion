// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapFailure.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum TransportBootstrapFailure: Error, Sendable, Equatable {
        case invalidBinding
        case invalidSigner
        case invalidRecipient
        case invalidSignature
        case invalidCanonicalDocument
        case invalidClaimCount
        case duplicateClaim
        case claimSetMismatch
        case invalidBlindRequest
        case invalidBlindResponse
        case invalidRegistrationSet
        case invalidKeyBundle
        case invalidAcknowledgementSet
        case invalidAnonymousMailboxCount
        case duplicateMailboxIdentity
        case identityReuse
        case invalidTimestamp
        case expired
        case invalidEvent
        case wrapperIdentityReuse
        case invalidRelayAllocation
        case publicationRejected
        case sourceLost
        case boundedBufferExceeded
        case cancelled
    }
}
#endif
