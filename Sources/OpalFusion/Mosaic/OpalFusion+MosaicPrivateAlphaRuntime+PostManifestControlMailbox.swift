// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestControlMailbox.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One authenticated control-roster-to-mailbox-key association.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestControlMailbox: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let controlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let eventVerificationKey:
            OpalCrypto.Signature.BIP340.VerificationKey

        @_spi(MosaicPrivateAlpha)
        public init(
            controlIdentity: Data,
            eventVerificationKey:
                OpalCrypto.Signature.BIP340.VerificationKey
        ) {
            self.controlIdentity = controlIdentity
            self.eventVerificationKey = eventVerificationKey
        }
    }
}
#endif
