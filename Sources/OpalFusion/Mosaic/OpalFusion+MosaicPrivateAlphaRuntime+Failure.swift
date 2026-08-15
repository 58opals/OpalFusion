// OpalFusion+MosaicPrivateAlphaRuntime+Failure.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum Failure: Swift.Error, Equatable, Sendable {
        case invalidIdentifierByteCount(expected: Int, actual: Int)
        case emptyExactBytes
        case opaqueByteCountLimitExceeded
        case invalidDiscoveryEpoch
        case invalidPrivateDeploymentProof
        case localControlIdentityNotInPrivateDeployment
        case unsupportedRecoveryVersion(UInt16)
        case malformedRecoverySnapshot
        case partialRecoverySnapshot
        case nonCanonicalRecoverySnapshot
        case recoveryBindingMismatch
        case contradictoryRecoverySnapshot
        case staleRecoveryTransition
        case exactReadbackMismatch
        case invalidStateTransition
        case recoveryRevisionOverflow
        case terminalEvidenceUnavailable
        case terminalEvidenceAlreadyClaimed
    }
}
#endif
