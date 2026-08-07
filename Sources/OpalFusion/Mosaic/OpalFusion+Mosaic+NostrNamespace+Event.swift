// OpalFusion+Mosaic+NostrNamespace+Event.swift

import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    struct Event: Sendable, Equatable {
        let identifier: OpalCrypto.Signature.Digest
        let publicKey: OpalCrypto.Signature.BIP340.VerificationKey
        let template: EventTemplate
        let signature: OpalCrypto.Signature.BIP340

        init(
            identifier: OpalCrypto.Signature.Digest,
            publicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            template: EventTemplate,
            signature: OpalCrypto.Signature.BIP340,
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
            guard signature.verify(
                digest: identifier,
                verificationKey: publicKey
            ) else {
                throw EventCodingError.signatureVerificationFailed
            }
            self.identifier = identifier
            self.publicKey = publicKey
            self.template = template
            self.signature = signature
        }
    }
}
