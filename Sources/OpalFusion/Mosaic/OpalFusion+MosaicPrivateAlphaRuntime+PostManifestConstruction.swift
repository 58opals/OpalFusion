// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestConstruction.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Opaque proof-bound construction for the existing selected post-manifest coordinator.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestConstruction: ~Copyable, Sendable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let localControlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let isConductor: Bool
        let bootstrap: OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRuntimeDriver.Bootstrap
        let completeManifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest
        let privateManifest: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestValidation
        let relaySet: OpalFusion.Mosaic.OpalMainnetAlpha.RelaySetDocument
        let recoveredTerminalEvidence: PostManifestTerminalEvidence?

        init(
            binding: Binding,
            localControlIdentity: Data,
            bootstrap: OpalFusion.Mosaic.OpalMainnetAlpha
                .PostManifestRuntimeDriver.Bootstrap,
            completeManifest: OpalFusion.Mosaic.OpalMainnetAlpha.RoundManifest,
            privateManifest: OpalFusion.Mosaic.OpalMainnetAlpha
                .PrivateDeploymentManifestValidation,
            relaySet: OpalFusion.Mosaic.OpalMainnetAlpha.RelaySetDocument,
            recoveredTerminalEvidence: PostManifestTerminalEvidence?,
            isConductor: Bool
        ) {
            self.binding = binding
            self.localControlIdentity = localControlIdentity
            self.bootstrap = bootstrap
            self.completeManifest = completeManifest
            self.privateManifest = privateManifest
            self.relaySet = relaySet
            self.recoveredTerminalEvidence = recoveredTerminalEvidence
            self.isConductor = isConductor
        }
    }
}
#endif
