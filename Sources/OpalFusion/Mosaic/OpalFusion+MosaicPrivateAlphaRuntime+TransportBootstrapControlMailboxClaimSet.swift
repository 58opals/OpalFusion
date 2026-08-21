// OpalFusion+MosaicPrivateAlphaRuntime+TransportBootstrapControlMailboxClaimSet.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Complete roster-authenticated control-mailbox claim set in control-key order.
    @_spi(MosaicPrivateAlpha)
    public struct TransportBootstrapControlMailboxClaimSet:
        Sendable,
        Equatable
    {
        @_spi(MosaicPrivateAlpha) public let claims:
            [TransportBootstrapControlMailboxClaim]
        @_spi(MosaicPrivateAlpha) public let authorizationKeyDocumentDigest:
            Data
        @_spi(MosaicPrivateAlpha) public let digest: Data
        @_spi(MosaicPrivateAlpha) public let canonicalDocument: Data

        init(
            claims: [TransportBootstrapControlMailboxClaim],
            authorizationKeyDocumentDigest: Data,
            digest: Data,
            canonicalDocument: Data
        ) {
            self.claims = claims
            self.authorizationKeyDocumentDigest =
                authorizationKeyDocumentDigest
            self.digest = digest
            self.canonicalDocument = canonicalDocument
        }
    }
}
#endif
