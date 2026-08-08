// MosaicManifestSignatureFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

/// Deterministic, test-only BIP340 material for Mosaic control-signature fixtures.
enum MosaicManifestSignatureFixtures {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    static func controlIdentity(
        scalarByte: UInt8
    ) -> Attempt.ControlIdentity {
        guard let keyMaterial = keyMaterialByScalar[scalarByte] else {
            preconditionFailure(
                "Manifest-signature fixtures require a registered test scalar."
            )
        }
        return keyMaterial.identity
    }

    static func manifestSignature(
        signer: Attempt.ControlIdentity,
        binding: Attempt.ManifestBinding
    ) -> Attempt.ManifestSignature {
        guard let signingKey = signingKeysByIdentity[signer] else {
            preconditionFailure(
                "Manifest-signature fixtures require a test control identity."
            )
        }
        let digest = try! OpalCrypto.Signature.Digest(
            rawRepresentation: Data(binding.roundIdentifier)
        )
        let auxiliaryRandomness = try! OpalCrypto.Signature.BIP340
            .AuxiliaryRandomness(
                rawRepresentation: Data(repeating: 0xA5, count: 32)
            )
        let signature = try! signingKey.signBIP340(
            digest: digest,
            auxiliaryRandomness: auxiliaryRandomness
        )
        return .init(
            signer: signer,
            rawRepresentation: Array(signature.rawRepresentation)
        )
    }

    static func manifestSignatures(
        for roster: Attempt.Roster,
        binding: Attempt.ManifestBinding
    ) -> [Attempt.ManifestSignature] {
        roster.controlIdentities.map {
            manifestSignature(signer: $0, binding: binding)
        }
    }

    static func manifestSignatureValidation(
        signer: Attempt.ControlIdentity,
        binding: Attempt.ManifestBinding
    ) -> Attempt.ManifestSignatureValidation {
        try! .init(
            validating: manifestSignature(signer: signer, binding: binding),
            for: binding
        )
    }

    static func manifestSignatureValidations(
        for roster: Attempt.Roster,
        binding: Attempt.ManifestBinding
    ) -> [Attempt.ManifestSignatureValidation] {
        roster.controlIdentities.map {
            manifestSignatureValidation(signer: $0, binding: binding)
        }
    }

    private struct KeyMaterial: Sendable {
        let identity: Attempt.ControlIdentity
        let signingKey: OpalCrypto.Secp256k1.SigningKey
    }

    private static let keyMaterialByScalar: [UInt8: KeyMaterial] = Dictionary(
        uniqueKeysWithValues: (
            Array(1 ... 10) + [21] + Array(65 ... 73) + [254]
        ).map {
            let scalarByte = UInt8($0)
            return (scalarByte, makeKeyMaterial(for: scalarByte))
        }
    )

    private static let signingKeysByIdentity: [
        Attempt.ControlIdentity: OpalCrypto.Secp256k1.SigningKey
    ] = Dictionary(
        uniqueKeysWithValues: keyMaterialByScalar.values.map {
            ($0.identity, $0.signingKey)
        }
    )

    private static func makeKeyMaterial(
        for scalarByte: UInt8
    ) -> KeyMaterial {
        precondition(scalarByte != 0, "A secp256k1 private scalar must be nonzero.")
        let signingKey = try! OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
        return .init(
            identity: .init(
                validatedBytes: Array(
                    signingKey.bip340VerificationKey.rawRepresentation
                )
            ),
            signingKey: signingKey
        )
    }
}
