// MosaicMainnetAlphaPrivateDiscoveryValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha private discovery validation", .serialized)
struct MosaicMainnetAlphaPrivateDiscoveryValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

    @Test("Select acknowledge and admit one canonical candidate roster")
    func selectAcknowledgeAndAdmitCanonicalCandidateRoster() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let selection = try makeSelection(beacons: fixture.beacons)
        let reversedSelection = try makeSelection(
            beacons: fixture.beacons.reversed()
        )

        #expect(selection.selectedBeacons.count == 9)
        #expect(selection == reversedSelection)
        #expect(selection.candidateSetDigest.count == 32)
        for beacon in fixture.beacons {
            #expect(beacon.claimedWorkBitCount >= 20)
            #expect(
                try Alpha.AvailabilityBeaconDocument.decode(
                    from: beacon.canonicalBytes
                ) == beacon
            )
        }

        let acknowledgements = try selection.selectedBeacons.map { beacon in
            try MosaicPrivateDeploymentFixtures.makeAcknowledgement(
                selection: selection,
                candidate: fixture.candidate(
                    for: beacon.core.discoveryIdentity
                )
            )
        }
        let acknowledgementSet = try Alpha
            .CandidateSetAcknowledgementSetDocument(
                acknowledgements: Array(acknowledgements.reversed()),
                candidateSelection: selection
            )
        #expect(
            try Alpha.CandidateSetAcknowledgementSetDocument.decode(
                from: acknowledgementSet.canonicalBytes,
                candidateSelection: selection
            ) == acknowledgementSet
        )

        let controlCandidates = try (21 ... 29).map {
            try MosaicPrivateDeploymentFixtures.CandidateKeyMaterial(
                scalar: UInt8($0)
            )
        }
        let admissions = try zip(
            selection.selectedBeacons,
            controlCandidates
        ).map { beacon, controlCandidate in
            try MosaicPrivateDeploymentFixtures.makeAdmission(
                selection: selection,
                discoveryCandidate: fixture.candidate(
                    for: beacon.core.discoveryIdentity
                ),
                controlCandidate: controlCandidate
            )
        }
        let roster = try Alpha.ControlRosterValidation(
            admissions: Array(admissions.reversed()),
            candidateSelection: selection,
            acknowledgementSet: acknowledgementSet
        )
        let forwardRoster = try Alpha.ControlRosterValidation(
            admissions: admissions,
            candidateSelection: selection,
            acknowledgementSet: acknowledgementSet
        )

        #expect(roster == forwardRoster)
        #expect(roster.controlRosterDigest.count == 32)
        #expect(roster.controlRosterBinding.candidateCount == 9)
        #expect(
            try Alpha.CandidateAdmissionDocument.decode(
                from: admissions[0].canonicalBytes
            ) == admissions[0]
        )
        #expect(
            throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)
        ) {
            _ = try Alpha.CandidateAdmissionDocument.decode(
                from: admissions[0].canonicalBytes + [0]
            )
        }

        #expect(throws: (any Error).self) {
            _ = try Alpha.CandidateSetAcknowledgementSetDocument(
                acknowledgements: Array(acknowledgements.dropLast()),
                candidateSelection: selection
            )
        }
        #expect(throws: (any Error).self) {
            _ = try Alpha.CandidateSetAcknowledgementSetDocument(
                acknowledgements: acknowledgements + [acknowledgements[0]],
                candidateSelection: selection
            )
        }

        let duplicateControlAdmission = try MosaicPrivateDeploymentFixtures
            .makeAdmission(
                selection: selection,
                discoveryCandidate: fixture.candidate(
                    for: selection.selectedBeacons[1].core.discoveryIdentity
                ),
                controlCandidate: controlCandidates[0]
            )
        var duplicateControls = admissions
        duplicateControls[1] = duplicateControlAdmission
        #expect(throws: (any Error).self) {
            _ = try Alpha.ControlRosterValidation(
                admissions: duplicateControls,
                candidateSelection: selection,
                acknowledgementSet: acknowledgementSet
            )
        }
    }

    @Test("Reject insufficient incorrect and invalidly signed work")
    func rejectInsufficientIncorrectAndInvalidlySignedWork() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let validBeacon = fixture.beacons[0]
        let expectedWork = validBeacon.claimedWorkBitCount

        #expect(
            throws: Alpha.AvailabilityBeaconDocument.ValidationError
                .workBitCountMismatch(
                    expected: expectedWork,
                    actual: expectedWork + 1
                )
        ) {
            _ = try Alpha.AvailabilityBeaconDocument(
                core: validBeacon.core,
                claimedWorkBitCount: expectedWork + 1,
                signature: validBeacon.signature
            )
        }
        var invalidSignature = validBeacon.signature
        invalidSignature[0] ^= 0x01
        #expect(
            throws: Alpha.AvailabilityBeaconDocument.ValidationError.invalidSignature
        ) {
            _ = try Alpha.AvailabilityBeaconDocument(
                core: validBeacon.core,
                claimedWorkBitCount: expectedWork,
                signature: invalidSignature
            )
        }

        let candidate = fixture.candidates[0]
        let expiry = try Alpha.PrivateDeploymentPolicy.frozen
            .preManifestDeadlines(
                forEpochStartingAt: fixture.epochStart
            ).beaconCutoff
        var nonce: UInt64 = 0
        var core: Alpha.AvailabilityBeaconCoreDocument
        var actualWork: UInt16
        repeat {
            core = try .init(
                discoveryEpochStartUnixSeconds: fixture.epochStart,
                opaquePoolIdentifier: fixture.pool.opaqueIdentifier,
                discoveryIdentity: candidate.identity,
                relaySetDigest: fixture.relaySet.digest,
                proofOfWorkNonce: nonce,
                expiryUnixSeconds: expiry
            )
            actualWork = MosaicPrivateDeploymentFixtures.leadingZeroBitCount(
                in: core.workDigest
            )
            nonce += 1
        } while actualWork >= 20
        let digest = Alpha.AvailabilityBeaconDocument.deriveSignatureDigest(
            core: core,
            claimedWorkBitCount: actualWork
        )
        let signature = try MosaicPrivateDeploymentFixtures.sign(
            digestBytes: digest,
            using: candidate.signingKey,
            auxiliaryByte: 0xC1
        )
        #expect(
            throws: Alpha.AvailabilityBeaconDocument.ValidationError
                .insufficientWork(actual: actualWork)
        ) {
            _ = try Alpha.AvailabilityBeaconDocument(
                core: core,
                claimedWorkBitCount: actualWork,
                signature: signature
            )
        }
    }

}
