// OpalFusion+Mosaic+Attempt+ManifestSignature.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.Attempt {
    /// One unverified control signature carried inside an authenticated manifest message.
    struct ManifestSignature: Sendable, Equatable {
        let signer: ControlIdentity
        let rawRepresentation: [UInt8]

        init(
            signer: ControlIdentity,
            rawRepresentation: [UInt8]
        ) {
            self.signer = signer
            self.rawRepresentation = Array(rawRepresentation)
        }
    }

    /// Proof that one supplied control key produced a valid BIP340 signature over a round identifier.
    ///
    /// This proves only the signature over `binding.roundIdentifier`. The unresolved complete-manifest
    /// schema remains responsible for deriving and validating `binding.manifestDigest`.
    struct ManifestSignatureValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidControlIdentityByteCount(actual: Int)
            case invalidControlIdentity
            case invalidSignatureByteCount(actual: Int)
            case invalidSignature
            case signatureVerificationFailed
        }

        let signer: ControlIdentity
        let binding: ManifestBinding

        init(
            validating signature: ManifestSignature,
            for binding: ManifestBinding
        ) throws(ValidationError) {
            guard signature.signer.validatedBytes.count == 32 else {
                throw ValidationError.invalidControlIdentityByteCount(
                    actual: signature.signer.validatedBytes.count
                )
            }

            let verificationKey: OpalCrypto.Signature.BIP340.VerificationKey
            do {
                verificationKey = try .init(
                    rawRepresentation: Data(signature.signer.validatedBytes)
                )
            } catch {
                throw ValidationError.invalidControlIdentity
            }

            guard signature.rawRepresentation.count == 64 else {
                throw ValidationError.invalidSignatureByteCount(
                    actual: signature.rawRepresentation.count
                )
            }

            let parsedSignature: OpalCrypto.Signature.BIP340
            do {
                parsedSignature = try .init(
                    rawRepresentation: Data(signature.rawRepresentation)
                )
            } catch {
                throw ValidationError.invalidSignature
            }

            let digest: OpalCrypto.Signature.Digest
            do {
                digest = try .init(
                    rawRepresentation: Data(binding.roundIdentifier)
                )
            } catch {
                preconditionFailure(
                    "ManifestBinding always contains a 32-byte round identifier."
                )
            }

            guard parsedSignature.verify(
                digest: digest,
                verificationKey: verificationKey
            ) else {
                throw ValidationError.signatureVerificationFailed
            }

            self.signer = signature.signer
            self.binding = binding
        }
    }
}
