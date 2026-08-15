// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestAnonymousMailboxes.swift

#if os(macOS)
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Role-limited anonymous mailbox capabilities restored for one exact attempt.
    @_spi(MosaicPrivateAlpha)
    public enum PostManifestAnonymousMailboxes: Sendable {
        case contributor([
            OpalCrypto.Signature.BIP340.VerificationKey
        ])
        case conductor([OpalCrypto.Secp256k1.SigningKey])
    }
}
#endif
