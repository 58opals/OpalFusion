// MosaicTranscriptAcknowledgementValidator.swift

import Foundation
import Testing
@testable import OpalFusion

@Suite("Mosaic transcript acknowledgement signatures")
struct MosaicTranscriptAcknowledgementValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    @Test(
        "Pin the profile-separated pre-sign acknowledgement digest",
        arguments: [
            (
                OpalFusion.Mosaic.Profile.draft1,
                "686c50b9c5b6209eaca1883b673096836c784f7bca511ee07cd4d3e98ea078a8"
            ),
            (
                OpalFusion.Mosaic.Profile.opalV0,
                "95aeb2c29927e2d11aabce7b92202b7617df43d3d657edc898627779a6785b58"
            ),
        ]
    )
    func pinDigestVector(
        profile: OpalFusion.Mosaic.Profile,
        expectedHexadecimal: String
    ) {
        let digest = Attempt.TranscriptAcknowledgementValidation.signatureDigest(
            profile: profile,
            roundIdentifier: Array(repeating: 0x11, count: 32),
            transcriptRoot: Array(repeating: 0x22, count: 32)
        )

        #expect(hexadecimal(Array(digest.rawRepresentation)) == expectedHexadecimal)
    }

    @Test(
        "Accept valid BIP340 acknowledgements under each exact profile domain",
        arguments: OpalFusion.Mosaic.Profile.allCases
    )
    func acceptValidAcknowledgement(
        profile: OpalFusion.Mosaic.Profile
    ) throws {
        let binding = try makeBinding(roundByte: 0x31)
        let root = try makeRoot(byte: 0x32)
        let contributor = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 1
        )
        let acknowledgement = MosaicManifestSignatureFixtures
            .transcriptAcknowledgement(
                contributor: contributor,
                binding: binding,
                transcriptRoot: root,
                profile: profile
            )

        let validation = try Attempt.TranscriptAcknowledgementValidation(
            validating: acknowledgement,
            profile: profile
        )

        #expect(validation.contributor == contributor)
        #expect(validation.profile == profile)
        #expect(validation.roundIdentifier == binding.roundIdentifier)
        #expect(validation.transcriptRoot == root)
    }

    @Test("Reject malformed acknowledgement field widths before verification")
    func rejectMalformedFieldWidths() throws {
        let binding = try makeBinding(roundByte: 0x41)
        let root = try makeRoot(byte: 0x42)
        let contributor = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 2
        )
        let valid = MosaicManifestSignatureFixtures.transcriptAcknowledgement(
            contributor: contributor,
            binding: binding,
            transcriptRoot: root
        )

        #expect(
            throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                .invalidControlIdentityByteCount(actual: 31)
        ) {
            _ = try Attempt.TranscriptAcknowledgementValidation(
                validating: .init(
                    contributor: .init(validatedBytes: Array(repeating: 0, count: 31)),
                    roundIdentifier: valid.roundIdentifier,
                    transcriptRoot: valid.transcriptRoot,
                    rawRepresentation: valid.rawRepresentation
                ),
                profile: .opalV0
            )
        }
        #expect(
            throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                .invalidRoundIdentifierByteCount(actual: 31)
        ) {
            _ = try Attempt.TranscriptAcknowledgementValidation(
                validating: .init(
                    contributor: contributor,
                    roundIdentifier: Array(repeating: 0, count: 31),
                    transcriptRoot: valid.transcriptRoot,
                    rawRepresentation: valid.rawRepresentation
                ),
                profile: .opalV0
            )
        }
        #expect(
            throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                .invalidTranscriptRootByteCount(actual: 33)
        ) {
            _ = try Attempt.TranscriptAcknowledgementValidation(
                validating: .init(
                    contributor: contributor,
                    roundIdentifier: valid.roundIdentifier,
                    transcriptRoot: Array(repeating: 0, count: 33),
                    rawRepresentation: valid.rawRepresentation
                ),
                profile: .opalV0
            )
        }
        #expect(
            throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                .invalidSignatureByteCount(actual: 63)
        ) {
            _ = try Attempt.TranscriptAcknowledgementValidation(
                validating: .init(
                    contributor: contributor,
                    roundIdentifier: valid.roundIdentifier,
                    transcriptRoot: valid.transcriptRoot,
                    rawRepresentation: Array(repeating: 0, count: 63)
                ),
                profile: .opalV0
            )
        }
        #expect(
            throws: Attempt.TranscriptRoot.ValidationError.invalidByteCount(actual: 31)
        ) {
            _ = try Attempt.TranscriptRoot(
                validating: Array(repeating: 0, count: 31)
            )
        }
    }

    @Test("Reject invalid control keys and BIP340 encodings")
    func rejectInvalidRepresentations() throws {
        let binding = try makeBinding(roundByte: 0x51)
        let root = try makeRoot(byte: 0x52)
        let contributor = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 3
        )

        #expect(
            throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                .invalidControlIdentity
        ) {
            _ = try Attempt.TranscriptAcknowledgementValidation(
                validating: .init(
                    contributor: .init(validatedBytes: Array(repeating: 0xFF, count: 32)),
                    roundIdentifier: binding.roundIdentifier,
                    transcriptRoot: root.validatedBytes,
                    rawRepresentation: Array(repeating: 0, count: 64)
                ),
                profile: .opalV0
            )
        }
        #expect(
            throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                .invalidSignature
        ) {
            _ = try Attempt.TranscriptAcknowledgementValidation(
                validating: .init(
                    contributor: contributor,
                    roundIdentifier: binding.roundIdentifier,
                    transcriptRoot: root.validatedBytes,
                    rawRepresentation: Array(repeating: 0xFF, count: 64)
                ),
                profile: .opalV0
            )
        }
    }

    @Test("Reject profile, round, root, contributor, and signature substitutions")
    func rejectSignedFieldSubstitutions() throws {
        let binding = try makeBinding(roundByte: 0x61)
        let root = try makeRoot(byte: 0x62)
        let contributor = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 4
        )
        let valid = MosaicManifestSignatureFixtures.transcriptAcknowledgement(
            contributor: contributor,
            binding: binding,
            transcriptRoot: root
        )
        let otherContributor = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 5
        )
        var changedSignature = valid.rawRepresentation
        changedSignature[changedSignature.count - 1] ^= 0x01
        let substitutions: [Attempt.TranscriptAcknowledgement] = [
            .init(
                contributor: otherContributor,
                roundIdentifier: valid.roundIdentifier,
                transcriptRoot: valid.transcriptRoot,
                rawRepresentation: valid.rawRepresentation
            ),
            .init(
                contributor: contributor,
                roundIdentifier: Array(repeating: 0x63, count: 32),
                transcriptRoot: valid.transcriptRoot,
                rawRepresentation: valid.rawRepresentation
            ),
            .init(
                contributor: contributor,
                roundIdentifier: valid.roundIdentifier,
                transcriptRoot: Array(repeating: 0x64, count: 32),
                rawRepresentation: valid.rawRepresentation
            ),
            .init(
                contributor: contributor,
                roundIdentifier: valid.roundIdentifier,
                transcriptRoot: valid.transcriptRoot,
                rawRepresentation: changedSignature
            ),
        ]

        for substitution in substitutions {
            #expect(
                throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                    .signatureVerificationFailed
            ) {
                _ = try Attempt.TranscriptAcknowledgementValidation(
                    validating: substitution,
                    profile: .opalV0
                )
            }
        }
        #expect(
            throws: Attempt.TranscriptAcknowledgementValidation.ValidationError
                .signatureVerificationFailed
        ) {
            _ = try Attempt.TranscriptAcknowledgementValidation(
                validating: valid,
                profile: .draft1
            )
        }
    }

    private func makeBinding(
        roundByte: UInt8
    ) throws -> Attempt.ManifestBinding {
        try .init(
            validatedRoundIdentifier: Array(repeating: roundByte, count: 32),
            validatedManifestDigest: Array(repeating: 0xA5, count: 32)
        )
    }

    private func makeRoot(byte: UInt8) throws -> Attempt.TranscriptRoot {
        try .init(validating: Array(repeating: byte, count: 32))
    }

    private func hexadecimal(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }
}
