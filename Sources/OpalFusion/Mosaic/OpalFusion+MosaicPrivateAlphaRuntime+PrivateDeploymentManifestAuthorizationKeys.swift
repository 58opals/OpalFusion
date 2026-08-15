// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentManifestAuthorizationKeys.swift

#if os(macOS)
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// The two distinct public blind-authorization keys signed into the manifest.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentManifestAuthorizationKeys: Sendable {
        let component: OpalCrypto.RSABSSA.VerificationKey
        let bchSignature: OpalCrypto.RSABSSA.VerificationKey

        @_spi(MosaicPrivateAlpha)
        public init(
            component: OpalCrypto.RSABSSA.VerificationKey,
            bchSignature: OpalCrypto.RSABSSA.VerificationKey
        ) {
            self.component = component
            self.bchSignature = bchSignature
        }
    }
}
#endif
