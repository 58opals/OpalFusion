// OpalFusion+Mosaic+NostrNamespace+UnsignedEvent.swift

import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    /// A NIP-01 event with a validated identifier and no signature.
    ///
    /// NIP-59 calls this unsigned form a rumor. Authenticity is established by
    /// the enclosing signed seal rather than by this value alone.
    struct UnsignedEvent: Sendable, Equatable {
        let identifier: OpalCrypto.Signature.Digest
        let publicKey: OpalCrypto.Signature.BIP340.VerificationKey
        let template: EventTemplate

        init(
            publicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            template: EventTemplate,
            limits: EventCodingLimits
        ) throws {
            self.identifier = try EventCodec.identifier(
                publicKey: publicKey,
                template: template,
                limits: limits
            )
            self.publicKey = publicKey
            self.template = template
        }

        init(
            identifier: OpalCrypto.Signature.Digest,
            publicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            template: EventTemplate,
            limits: EventCodingLimits
        ) throws {
            let expectedIdentifier = try EventCodec.identifier(
                publicKey: publicKey,
                template: template,
                limits: limits
            )
            guard identifier == expectedIdentifier else {
                throw EventCodingError.identifierMismatch
            }
            self.identifier = identifier
            self.publicKey = publicKey
            self.template = template
        }
    }
}
