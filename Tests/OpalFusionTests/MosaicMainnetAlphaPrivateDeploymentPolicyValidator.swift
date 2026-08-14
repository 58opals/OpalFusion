// MosaicMainnetAlphaPrivateDeploymentPolicyValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha private-deployment policy validation")
struct MosaicMainnetAlphaPrivateDeploymentPolicyValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

    @Test("Freeze aligned discovery and post-manifest deadlines")
    func freezeAlignedDiscoveryAndPostManifestDeadlines() throws {
        let policy = Alpha.PrivateDeploymentPolicy.frozen
        let epochStart: UInt64 = 1_800_000_000
        let preManifest = try policy.preManifestDeadlines(
            forEpochStartingAt: epochStart
        )

        #expect(policy.discoveryEpochDurationSeconds == 300)
        #expect(policy.minimumLeadingZeroWorkBitCount == 20)
        #expect(policy.epochStart(containing: epochStart + 299) == epochStart)
        #expect(preManifest.beaconCutoff == epochStart + 60)
        #expect(preManifest.candidateSetAgreement == epochStart + 90)
        #expect(preManifest.controlRosterAgreement == epochStart + 120)
        #expect(preManifest.roleCommitment == epochStart + 150)
        #expect(preManifest.roleReveal == epochStart + 180)
        #expect(preManifest.manifestAgreement == epochStart + 240)

        let phaseStart = epochStart + 240
        let postManifest = try policy.postManifestDeadlines(
            forPhaseStartingAt: phaseStart
        )
        #expect(postManifest.walletReservation == phaseStart + 60)
        #expect(postManifest.groupedCommitment == phaseStart + 120)
        #expect(postManifest.anonymousComponentSubmission == phaseStart + 240)
        #expect(postManifest.transcriptAgreement == phaseStart + 300)
        #expect(postManifest.bchSigning == phaseStart + 360)
        #expect(
            policy.reservationLeaseExpirationUnixSeconds(
                for: postManifest
            ) == postManifest.bchSigning
        )
    }

    @Test("Reject unaligned epochs and deadline overflow")
    func rejectUnalignedEpochsAndDeadlineOverflow() {
        #expect(
            throws: Alpha.PrivateDeploymentPolicy.ValidationError
                .unalignedEpochStart(1_800_000_001)
        ) {
            _ = try Alpha.PrivateDeploymentPolicy.frozen
                .preManifestDeadlines(
                    forEpochStartingAt: 1_800_000_001
                )
        }
        #expect(
            throws: Alpha.PrivateDeploymentPolicy.ValidationError.deadlineOverflow
        ) {
            _ = try Alpha.PrivateDeploymentPolicy.frozen
                .postManifestDeadlines(
                    forPhaseStartingAt: UInt64.max - 59
                )
        }
    }

    @Test("Round trip a caller-owned opaque pool document")
    func roundTripCallerOwnedOpaquePoolDocument() throws {
        let identifier = (0 ..< 32).map(UInt8.init)
        let document = try Alpha.OpaquePoolDocument(
            appGeneratedOpaqueIdentifier: identifier
        )

        #expect(try Alpha.OpaquePoolDocument.decode(from: document.canonicalBytes) == document)
        #expect(document.digest.count == 32)
        #expect(
            document.digest
                != (try Alpha.OpaquePoolDocument(
                    appGeneratedOpaqueIdentifier: Array(identifier.reversed())
                )).digest
        )
        #expect(throws: (any Error).self) {
            _ = try Alpha.OpaquePoolDocument(
                appGeneratedOpaqueIdentifier: Array(identifier.dropLast())
            )
        }
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Alpha.OpaquePoolDocument.decode(
                from: document.canonicalBytes + [0]
            )
        }
        _ = try Alpha.OpaquePoolBindingValidation(
            validating: document,
            expectedOpaqueIdentifier: identifier
        )
        #expect(
            throws: Alpha.OpaquePoolBindingValidation.ValidationError
                .identifierMismatch
        ) {
            _ = try Alpha.OpaquePoolBindingValidation(
                validating: document,
                expectedOpaqueIdentifier: Array(repeating: 0xFF, count: 32)
            )
        }
    }
}
