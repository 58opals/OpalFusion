// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestMailboxCapabilities.swift

#if os(macOS)
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Authenticated mailbox projection plus the local recipient decryption capability.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestMailboxCapabilities: Sendable {
        @_spi(MosaicPrivateAlpha) public let controlMailboxes:
            [PostManifestControlMailbox]
        @_spi(MosaicPrivateAlpha) public let localControlRecipientSigningKey:
            OpalCrypto.Secp256k1.SigningKey
        @_spi(MosaicPrivateAlpha) public let anonymous:
            PostManifestAnonymousMailboxes

        init(
            controlMailboxes: [PostManifestControlMailbox],
            localControlRecipientSigningKey:
                OpalCrypto.Secp256k1.SigningKey,
            anonymous: PostManifestAnonymousMailboxes
        ) {
            self.controlMailboxes = controlMailboxes
            self.localControlRecipientSigningKey =
                localControlRecipientSigningKey
            self.anonymous = anonymous
        }
    }
}
#endif
