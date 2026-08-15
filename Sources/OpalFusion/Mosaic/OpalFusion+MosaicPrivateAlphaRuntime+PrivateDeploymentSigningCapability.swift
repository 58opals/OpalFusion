// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentSigningCapability.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One-use local signing capability for one package-constructed private-deployment event.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentSigningCapability: ~Copyable, Sendable {
        let signingKey: OpalCrypto.Secp256k1.SigningKey
        let documentAuxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness
        let eventAuxiliaryRandomness:
            OpalCrypto.Signature.BIP340.AuxiliaryRandomness

        @_spi(MosaicPrivateAlpha)
        public init(
            signingKey: OpalCrypto.Secp256k1.SigningKey,
            documentAuxiliaryRandomness:
                OpalCrypto.Signature.BIP340.AuxiliaryRandomness,
            eventAuxiliaryRandomness:
                OpalCrypto.Signature.BIP340.AuxiliaryRandomness
        ) {
            self.signingKey = signingKey
            self.documentAuxiliaryRandomness =
                documentAuxiliaryRandomness
            self.eventAuxiliaryRandomness = eventAuxiliaryRandomness
        }

        var verificationKey:
            OpalCrypto.Signature.BIP340.VerificationKey {
            signingKey.bip340VerificationKey
        }

        func signDocumentDigest(_ digestBytes: [UInt8]) throws -> [UInt8] {
            let digest = try OpalCrypto.Signature.Digest(
                rawRepresentation: Data(digestBytes)
            )
            return try [UInt8](signingKey.signBIP340(
                digest: digest,
                auxiliaryRandomness: documentAuxiliaryRandomness
            ).rawRepresentation)
        }
    }
}
#endif
