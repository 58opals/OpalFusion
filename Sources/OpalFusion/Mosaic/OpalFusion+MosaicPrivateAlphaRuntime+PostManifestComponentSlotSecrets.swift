// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestComponentSlotSecrets.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-restored secret material for one package-validated contributor slot.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestComponentSlotSecrets: Sendable {
        let salt: Data
        let pedersenNonce: OpalCrypto.Pedersen.Nonce
        let communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey
        let componentEnvelopePrivateKey: OpalCrypto.Secp256k1.PrivateKey
        let bchSignatureEnvelopePrivateKey: OpalCrypto.Secp256k1.PrivateKey
        let componentAuthorizationNonce: Data
        let bchSignatureAuthorizationNonce: Data
        let recipientEventIdentity: Data

        @_spi(MosaicPrivateAlpha)
        public init(
            salt: Data,
            pedersenNonce: OpalCrypto.Pedersen.Nonce,
            communicationPrivateKey: OpalCrypto.Secp256k1.PrivateKey,
            componentEnvelopePrivateKey: OpalCrypto.Secp256k1.PrivateKey,
            bchSignatureEnvelopePrivateKey:
                OpalCrypto.Secp256k1.PrivateKey,
            componentAuthorizationNonce: Data,
            bchSignatureAuthorizationNonce: Data,
            recipientEventIdentity: Data
        ) {
            self.salt = salt
            self.pedersenNonce = pedersenNonce
            self.communicationPrivateKey = communicationPrivateKey
            self.componentEnvelopePrivateKey = componentEnvelopePrivateKey
            self.bchSignatureEnvelopePrivateKey =
                bchSignatureEnvelopePrivateKey
            self.componentAuthorizationNonce = componentAuthorizationNonce
            self.bchSignatureAuthorizationNonce =
                bchSignatureAuthorizationNonce
            self.recipientEventIdentity = recipientEventIdentity
        }

        func makeInternal() throws -> OpalFusion.Mosaic.OpalMainnetAlpha
            .ComponentSlotSecrets {
            try .init(
                salt: Array(salt),
                pedersenNonce: pedersenNonce,
                communicationPrivateKey: communicationPrivateKey,
                componentEnvelopePrivateKey: componentEnvelopePrivateKey,
                bchSignatureEnvelopePrivateKey:
                    bchSignatureEnvelopePrivateKey,
                componentAuthorizationNonce:
                    Array(componentAuthorizationNonce),
                bchSignatureAuthorizationNonce:
                    Array(bchSignatureAuthorizationNonce),
                recipientEventIdentity: Array(recipientEventIdentity)
            )
        }
    }
}
#endif
