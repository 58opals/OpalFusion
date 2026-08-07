// OpalFusion+Mosaic+NostrNamespace+EventSigner.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    enum EventSigner {
        static func sign(
            _ template: EventTemplate,
            using signingKey: OpalCrypto.Secp256k1.SigningKey,
            auxiliaryRandomness: OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
            limits: EventCodingLimits
        ) throws -> Event {
            let publicKey = signingKey.bip340VerificationKey
            let identifier = try EventCodec.identifier(
                publicKey: publicKey,
                template: template,
                limits: limits
            )
            let signature = try signingKey.signBIP340(
                digest: identifier,
                auxiliaryRandomness: auxiliaryRandomness
            )
            return try Event(
                identifier: identifier,
                publicKey: publicKey,
                template: template,
                signature: signature,
                limits: limits
            )
        }
    }
}
