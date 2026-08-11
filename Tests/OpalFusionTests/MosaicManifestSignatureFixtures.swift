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
        binding: Attempt.ManifestBinding,
        auxiliaryRandomnessByte: UInt8 = 0xA5
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
                rawRepresentation: Data(
                    repeating: auxiliaryRandomnessByte,
                    count: 32
                )
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
        binding: Attempt.ManifestBinding,
        auxiliaryRandomnessByte: UInt8 = 0xA5
    ) -> [Attempt.ManifestSignature] {
        roster.controlIdentities.map {
            manifestSignature(
                signer: $0,
                binding: binding,
                auxiliaryRandomnessByte: auxiliaryRandomnessByte
            )
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

    static func transcriptAcknowledgement(
        contributor: Attempt.ControlIdentity,
        binding: Attempt.ManifestBinding,
        transcriptRoot: Attempt.TranscriptRoot,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) -> Attempt.TranscriptAcknowledgement {
        guard let signingKey = signingKeysByIdentity[contributor] else {
            preconditionFailure(
                "Transcript-acknowledgement fixtures require a test control identity."
            )
        }
        let digest = Attempt.TranscriptAcknowledgementValidation.signatureDigest(
            profile: profile,
            roundIdentifier: binding.roundIdentifier,
            transcriptRoot: transcriptRoot.validatedBytes
        )
        let auxiliaryRandomness = try! OpalCrypto.Signature.BIP340
            .AuxiliaryRandomness(
                rawRepresentation: Data(repeating: 0x5A, count: 32)
            )
        let signature = try! signingKey.signBIP340(
            digest: digest,
            auxiliaryRandomness: auxiliaryRandomness
        )
        return .init(
            contributor: contributor,
            roundIdentifier: binding.roundIdentifier,
            transcriptRoot: transcriptRoot.validatedBytes,
            rawRepresentation: Array(signature.rawRepresentation)
        )
    }

    static func transcriptAcknowledgements(
        for contributors: [Attempt.ControlIdentity],
        binding: Attempt.ManifestBinding,
        transcriptRoot: Attempt.TranscriptRoot,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) -> [Attempt.TranscriptAcknowledgement] {
        contributors.map {
            transcriptAcknowledgement(
                contributor: $0,
                binding: binding,
                transcriptRoot: transcriptRoot,
                profile: profile
            )
        }
    }

    static func transcriptAcknowledgementValidation(
        contributor: Attempt.ControlIdentity,
        binding: Attempt.ManifestBinding,
        transcriptRoot: Attempt.TranscriptRoot,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) -> Attempt.TranscriptAcknowledgementValidation {
        try! .init(
            validating: transcriptAcknowledgement(
                contributor: contributor,
                binding: binding,
                transcriptRoot: transcriptRoot,
                profile: profile
            ),
            profile: profile
        )
    }

    static func transcriptAcknowledgementValidations(
        for contributors: [Attempt.ControlIdentity],
        binding: Attempt.ManifestBinding,
        transcriptRoot: Attempt.TranscriptRoot,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) -> [Attempt.TranscriptAcknowledgementValidation] {
        contributors.map {
            transcriptAcknowledgementValidation(
                contributor: $0,
                binding: binding,
                transcriptRoot: transcriptRoot,
                profile: profile
            )
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
