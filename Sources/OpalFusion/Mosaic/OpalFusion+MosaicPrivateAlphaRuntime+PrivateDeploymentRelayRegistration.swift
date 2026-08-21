// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentRelayRegistration.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One application-reviewed relay registry entry before canonicalization.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentRelayRegistration: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let endpoint: String
        @_spi(MosaicPrivateAlpha) public let reviewedOperatorRegistryLabel: String
        @_spi(MosaicPrivateAlpha) public let requiresNIP42Authentication: Bool
        @_spi(MosaicPrivateAlpha) public let requiresProofOfWork: Bool

        @_spi(MosaicPrivateAlpha)
        public init(
            endpoint: String,
            reviewedOperatorRegistryLabel: String,
            requiresNIP42Authentication: Bool,
            requiresProofOfWork: Bool
        ) {
            self.endpoint = endpoint
            self.reviewedOperatorRegistryLabel = reviewedOperatorRegistryLabel
            self.requiresNIP42Authentication = requiresNIP42Authentication
            self.requiresProofOfWork = requiresProofOfWork
        }
    }
}
#endif
