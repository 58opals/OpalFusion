// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentSignatureValidation.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Stateless BIP340 validation for private-deployment canonical documents.
    struct PrivateDeploymentSignatureValidation: Sendable {
        static func verify(
            signatureBytes: [UInt8],
            digestBytes: [UInt8],
            using verificationKey: OpalCrypto.Signature.BIP340.VerificationKey
        ) -> Bool {
            guard signatureBytes.count == 64, digestBytes.count == 32,
                  let signature = try? OpalCrypto.Signature.BIP340(
                      rawRepresentation: Data(signatureBytes)
                  ),
                  let digest = try? OpalCrypto.Signature.Digest(
                      rawRepresentation: Data(digestBytes)
                  ) else {
                return false
            }
            return signature.verify(
                digest: digest,
                verificationKey: verificationKey
            )
        }
    }
}
