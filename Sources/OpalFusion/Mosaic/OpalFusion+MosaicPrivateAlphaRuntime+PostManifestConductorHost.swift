// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestConductorHost.swift

#if os(macOS)
import OpalCrypto
import Security

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Restored non-exportable signing and typed chain capabilities for the conductor runtime.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestConductorHost: ~Copyable {
        let componentAuthorizationSecurityKey: SecKey
        let bchSignatureAuthorizationSecurityKey: SecKey
        let previousOutputSource: any OpalFusion.Host
            .MosaicPreviousOutputSource
        let controlSigningKey: OpalCrypto.Secp256k1.SigningKey
        let controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey

        @_spi(MosaicPrivateAlpha)
        public init(
            componentAuthorizationSecurityKey: SecKey,
            bchSignatureAuthorizationSecurityKey: SecKey,
            previousOutputSource: any OpalFusion.Host
                .MosaicPreviousOutputSource,
            controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
            controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey
        ) {
            self.componentAuthorizationSecurityKey =
                componentAuthorizationSecurityKey
            self.bchSignatureAuthorizationSecurityKey =
                bchSignatureAuthorizationSecurityKey
            self.previousOutputSource = previousOutputSource
            self.controlSigningKey = controlSigningKey
            self.controlEventSigningKey = controlEventSigningKey
        }
    }
}
#endif
