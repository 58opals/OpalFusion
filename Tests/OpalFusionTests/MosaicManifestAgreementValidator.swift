// MosaicManifestAgreementValidator.swift

@testable import OpalFusion
import Testing

@Suite("Mosaic manifest binding and unanimous agreement")
struct MosaicManifestAgreementValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    @Test("Manifest bindings preserve separate fixed-width round and complete-manifest identities")
    func validateManifestBindingWidths() throws {
        #expect(
            throws: Attempt.ManifestBinding.ValidationError
                .invalidRoundIdentifierByteCount(actual: 31)
        ) {
            _ = try Attempt.ManifestBinding(
                validatedRoundIdentifier: Array(repeating: 0x11, count: 31),
                validatedManifestDigest: Array(repeating: 0x22, count: 32)
            )
        }
        #expect(
            throws: Attempt.ManifestBinding.ValidationError
                .invalidManifestDigestByteCount(actual: 33)
        ) {
            _ = try Attempt.ManifestBinding(
                validatedRoundIdentifier: Array(repeating: 0x11, count: 32),
                validatedManifestDigest: Array(repeating: 0x22, count: 33)
            )
        }

        let binding = try makeBinding(roundByte: 0x11, manifestByte: 0x22)
        #expect(binding.roundIdentifier == Array(repeating: 0x11, count: 32))
        #expect(binding.manifestDigest == Array(repeating: 0x22, count: 32))

        let byteEqualBinding = try makeBinding(
            roundByte: 0x33,
            manifestByte: 0x33
        )
        #expect(
            byteEqualBinding.roundIdentifier
                == byteEqualBinding.manifestDigest
        )
    }

    @Test(
        "Agreement accepts every valid roster size and normalizes validation order",
        arguments: [7, 8, 9]
    )
    func validateUnanimousAgreement(candidateCount: Int) throws {
        let roster = try makeRoster(candidateCount: candidateCount)
        let binding = try makeBinding(roundByte: 0x31, manifestByte: 0x32)
        let validations = roster.controlIdentities.reversed().map {
            MosaicManifestSignatureFixtures.manifestSignatureValidation(
                signer: $0,
                binding: binding
            )
        }

        let agreement = try Attempt.ManifestAgreement(
            roster: roster,
            validatedSignatures: validations
        )

        #expect(agreement.binding == binding)
        #expect(validations.count == roster.candidateCount)
    }

    @Test("Contributors cannot form manifest agreement without the conductor")
    func requireConductorSignature() throws {
        let roster = try makeRoster(candidateCount: 7)
        let binding = try makeBinding(roundByte: 0x41, manifestByte: 0x42)
        let contributorValidations = roster.contributors.map {
            MosaicManifestSignatureFixtures.manifestSignatureValidation(
                signer: $0,
                binding: binding
            )
        }

        #expect(
            throws: Attempt.ManifestAgreement.ValidationError
                .missingSigners([roster.conductor])
        ) {
            _ = try Attempt.ManifestAgreement(
                roster: roster,
                validatedSignatures: contributorValidations
            )
        }
    }

    @Test("Round identifier and complete-manifest digest both participate in agreement")
    func rejectEitherBindingDifference() throws {
        let roster = try makeRoster(candidateCount: 7)
        let common = try makeBinding(roundByte: 0x51, manifestByte: 0x52)
        let changedRound = try makeBinding(roundByte: 0x53, manifestByte: 0x52)
        let changedManifest = try makeBinding(roundByte: 0x51, manifestByte: 0x54)

        for conflictingBinding in [changedRound, changedManifest] {
            var validations = roster.controlIdentities.map {
                MosaicManifestSignatureFixtures.manifestSignatureValidation(
                    signer: $0,
                    binding: common
                )
            }
            validations[validations.count - 1] = MosaicManifestSignatureFixtures
                .manifestSignatureValidation(
                    signer: validations[validations.count - 1].signer,
                    binding: conflictingBinding
                )

            #expect(
                throws: Attempt.ManifestAgreement.ValidationError
                    .bindingDisagreement
            ) {
                _ = try Attempt.ManifestAgreement(
                    roster: roster,
                    validatedSignatures: validations
                )
            }
        }
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

    private func makeRoster(candidateCount: Int) throws -> Attempt.Roster {
        try .init(
            members: (0 ..< candidateCount).map { index in
                .init(
                    controlIdentity: MosaicManifestSignatureFixtures
                        .controlIdentity(
                            scalarByte: UInt8(index + 1)
                        ),
                    role: index == 0 ? .conductor : .contributor
                )
            }
        )
    }
}
