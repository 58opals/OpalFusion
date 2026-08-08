// MosaicManifestSignatureValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic manifest control-signature validation")
struct MosaicManifestSignatureValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    @Test("Accept a valid BIP340 signature over the round identifier")
    func acceptValidSignature() throws {
        let binding = try makeBinding(roundByte: 0x11, manifestByte: 0x12)
        let signer = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 1
        )
        let signature = MosaicManifestSignatureFixtures.manifestSignature(
            signer: signer,
            binding: binding
        )

        let validation = try Attempt.ManifestSignatureValidation(
            validating: signature,
            for: binding
        )

        #expect(validation.signer == signer)
        #expect(validation.binding == binding)
    }

    @Test("Reject malformed BIP340 control keys and signatures")
    func rejectMalformedRepresentations() throws {
        let binding = try makeBinding(roundByte: 0x21, manifestByte: 0x22)
        let validSigner = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 2
        )

        #expect(
            throws: Attempt.ManifestSignatureValidation.ValidationError
                .invalidControlIdentityByteCount(actual: 31)
        ) {
            _ = try Attempt.ManifestSignatureValidation(
                validating: .init(
                    signer: .init(validatedBytes: Array(repeating: 0, count: 31)),
                    rawRepresentation: Array(repeating: 0, count: 64)
                ),
                for: binding
            )
        }
        #expect(
            throws: Attempt.ManifestSignatureValidation.ValidationError
                .invalidControlIdentity
        ) {
            _ = try Attempt.ManifestSignatureValidation(
                validating: .init(
                    signer: .init(validatedBytes: Array(repeating: 0xFF, count: 32)),
                    rawRepresentation: Array(repeating: 0, count: 64)
                ),
                for: binding
            )
        }
        #expect(
            throws: Attempt.ManifestSignatureValidation.ValidationError
                .invalidSignatureByteCount(actual: 63)
        ) {
            _ = try Attempt.ManifestSignatureValidation(
                validating: .init(
                    signer: validSigner,
                    rawRepresentation: Array(repeating: 0, count: 63)
                ),
                for: binding
            )
        }
        #expect(
            throws: Attempt.ManifestSignatureValidation.ValidationError
                .invalidSignature
        ) {
            _ = try Attempt.ManifestSignatureValidation(
                validating: .init(
                    signer: validSigner,
                    rawRepresentation: Array(repeating: 0xFF, count: 64)
                ),
                for: binding
            )
        }
    }

    @Test("Reject signatures for another round or control identity")
    func rejectWrongRoundAndSigner() throws {
        let signedBinding = try makeBinding(roundByte: 0x31, manifestByte: 0x32)
        let otherRound = try makeBinding(roundByte: 0x33, manifestByte: 0x32)
        let signer = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 3
        )
        let signature = MosaicManifestSignatureFixtures.manifestSignature(
            signer: signer,
            binding: signedBinding
        )

        #expect(
            throws: Attempt.ManifestSignatureValidation.ValidationError
                .signatureVerificationFailed
        ) {
            _ = try Attempt.ManifestSignatureValidation(
                validating: signature,
                for: otherRound
            )
        }

        let relabeled = Attempt.ManifestSignature(
            signer: MosaicManifestSignatureFixtures.controlIdentity(
                scalarByte: 4
            ),
            rawRepresentation: signature.rawRepresentation
        )
        #expect(
            throws: Attempt.ManifestSignatureValidation.ValidationError
                .signatureVerificationFailed
        ) {
            _ = try Attempt.ManifestSignatureValidation(
                validating: relabeled,
                for: signedBinding
            )
        }

        var changedBytes = signature.rawRepresentation
        changedBytes[changedBytes.count - 1] ^= 0x01
        #expect(
            throws: Attempt.ManifestSignatureValidation.ValidationError
                .signatureVerificationFailed
        ) {
            _ = try Attempt.ManifestSignatureValidation(
                validating: .init(
                    signer: signer,
                    rawRepresentation: changedBytes
                ),
                for: signedBinding
            )
        }
    }

    @Test("Keep complete-manifest digest linkage explicitly deferred")
    func preserveDeferredManifestDigestLinkage() throws {
        let signedBinding = try makeBinding(roundByte: 0x41, manifestByte: 0x42)
        let changedManifest = try makeBinding(
            roundByte: 0x41,
            manifestByte: 0x43
        )
        let signer = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 5
        )
        let signature = MosaicManifestSignatureFixtures.manifestSignature(
            signer: signer,
            binding: signedBinding
        )

        let validation = try Attempt.ManifestSignatureValidation(
            validating: signature,
            for: changedManifest
        )

        #expect(validation.binding == changedManifest)
    }

    private func makeBinding(
        roundByte: UInt8,
        manifestByte: UInt8
    ) throws -> Attempt.ManifestBinding {
        try .init(
            validatedRoundIdentifier: Array(repeating: roundByte, count: 32),
            validatedManifestDigest: Array(repeating: manifestByte, count: 32)
        )
    }
}
