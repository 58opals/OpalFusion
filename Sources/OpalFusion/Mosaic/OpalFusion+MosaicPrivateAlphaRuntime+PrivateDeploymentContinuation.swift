// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentContinuation.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Opaque restored private-deployment executor state for one exact binding.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentContinuation: Equatable, Sendable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let phase: Phase
        let proof: PrivateDeploymentProof?

        init(
            binding: Binding,
            phase: Phase,
            proof: PrivateDeploymentProof?
        ) {
            self.binding = binding
            self.phase = phase
            self.proof = proof
        }
    }
}
#endif
