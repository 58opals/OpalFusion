// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentConfigurationFailure.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    @_spi(MosaicPrivateAlpha)
    public enum PrivateDeploymentConfigurationFailure:
        Error,
        Sendable,
        Equatable
    {
        case invalidOpaquePoolIdentifier
        case invalidRelayEndpoint
        case invalidOperatorRegistryLabel
        case invalidRelayCount
        case duplicateRelayEndpoint
        case duplicateRelayOperator
        case unsupportedNIP42Authentication
        case unsupportedProofOfWork
    }
}
#endif
