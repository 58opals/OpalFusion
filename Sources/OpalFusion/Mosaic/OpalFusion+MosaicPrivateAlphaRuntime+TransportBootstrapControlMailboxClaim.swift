// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapControlMailboxClaim.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One roster member's signed binding to its fresh post-manifest control mailbox.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapControlMailboxClaim: Sendable, Equatable {
        @_spi(MosaicPrivateAlpha) public let controlIdentity: Data
        @_spi(MosaicPrivateAlpha) public let recipientEventIdentity: Data
        @_spi(MosaicPrivateAlpha) public let authorizationKeyDocumentDigest:
            Data
        @_spi(MosaicPrivateAlpha) public let blindedMessage: Data?
        @_spi(MosaicPrivateAlpha) public let expiryUnixSeconds: UInt64
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        let signature: Data

        init(
            controlIdentity: Data,
            recipientEventIdentity: Data,
            authorizationKeyDocumentDigest: Data,
            blindedMessage: Data?,
            expiryUnixSeconds: UInt64,
            canonicalDocument: Data,
            signature: Data
        ) {
            self.controlIdentity = controlIdentity
            self.recipientEventIdentity = recipientEventIdentity
            self.authorizationKeyDocumentDigest =
                authorizationKeyDocumentDigest
            self.blindedMessage = blindedMessage
            self.expiryUnixSeconds = expiryUnixSeconds
            self.canonicalDocument = canonicalDocument
            self.signature = signature
        }
    }
}
#endif
