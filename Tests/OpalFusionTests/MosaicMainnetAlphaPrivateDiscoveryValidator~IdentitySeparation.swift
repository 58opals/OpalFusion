// MosaicMainnetAlphaPrivateDiscoveryValidator~IdentitySeparation.swift

import Testing
@testable import OpalFusion

extension MosaicMainnetAlphaPrivateDiscoveryValidator {
    @Test("Reject overlap between any discovery and control identity")
    func rejectGlobalDiscoveryControlIdentityOverlap() throws {
        let fixture = try MosaicPrivateDeploymentFixtures.discovery
        let selection = try makeSelection(beacons: fixture.beacons)
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
                acknowledgements: acknowledgements,
                candidateSelection: selection
            )
        let controlCandidates = try (21 ... 29).map {
            try MosaicPrivateDeploymentFixtures.CandidateKeyMaterial(
                scalar: UInt8($0)
            )
        }
        var admissions = try zip(
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
        let overlappingDiscoveryCandidate = fixture.candidate(
            for: selection.selectedBeacons[0].core.discoveryIdentity
        )
        let otherDiscoveryCandidate = fixture.candidate(
            for: selection.selectedBeacons[1].core.discoveryIdentity
        )
        admissions[1] = try MosaicPrivateDeploymentFixtures.makeAdmission(
            selection: selection,
            discoveryCandidate: otherDiscoveryCandidate,
            controlCandidate: overlappingDiscoveryCandidate
        )

        #expect(
            throws: Alpha.ControlRosterValidation.ValidationError
                .discoveryControlIdentityOverlap(
                    [UInt8](overlappingDiscoveryCandidate.identity.rawRepresentation)
                )
        ) {
            _ = try Alpha.ControlRosterValidation(
                admissions: admissions,
                candidateSelection: selection,
                acknowledgementSet: acknowledgementSet
            )
        }
    }
}
