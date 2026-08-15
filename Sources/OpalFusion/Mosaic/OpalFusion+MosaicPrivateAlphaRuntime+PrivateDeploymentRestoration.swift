// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentRestoration.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    static func restorePrivateDeploymentProof(
        discoveryEpochStartUnixSeconds: UInt64,
        canonicalDocuments: [Data]
    ) throws -> PrivateDeploymentProof {
        guard canonicalDocuments.count >= 47,
              (canonicalDocuments.count - 5).isMultiple(of: 6) else {
            throw Failure.invalidPrivateDeploymentProof
        }
        let candidateCount = (canonicalDocuments.count - 5) / 6
        guard (7 ... 9).contains(candidateCount) else {
            throw Failure.invalidPrivateDeploymentProof
        }
        var cursor = 2
        func take(_ count: Int) -> [Data] {
            defer { cursor += count }
            return Array(canonicalDocuments[cursor ..< cursor + count])
        }
        let beacons = take(candidateCount)
        let acknowledgements = take(candidateCount)
        let admissions = take(candidateCount)
        let commitments = take(candidateCount)
        let reveals = take(candidateCount)
        let nonceAllocation = canonicalDocuments[cursor]
        cursor += 1
        let proposal = canonicalDocuments[cursor]
        cursor += 1
        let signatures = take(candidateCount)
        let completeManifest = canonicalDocuments[cursor]
        cursor += 1
        guard cursor == canonicalDocuments.endIndex else {
            throw Failure.invalidPrivateDeploymentProof
        }
        let proof = try validatePrivateDeployment(
            discoveryEpochStartUnixSeconds:
                discoveryEpochStartUnixSeconds,
            opaquePoolDocument: canonicalDocuments[0],
            relaySetDocument: canonicalDocuments[1],
            availabilityBeaconEvents: try beacons.map(
                PrivateDeploymentEvent.decodeRecoveryBytes
            ),
            candidateSetAcknowledgementEvents: try acknowledgements.map(
                PrivateDeploymentEvent.decodeRecoveryBytes
            ),
            candidateAdmissionEvents: try admissions.map(
                PrivateDeploymentEvent.decodeRecoveryBytes
            ),
            roleCommitmentEvents: try commitments.map(
                PrivateDeploymentEvent.decodeRecoveryBytes
            ),
            roleRevealEvents: try reveals.map(
                PrivateDeploymentEvent.decodeRecoveryBytes
            ),
            contributorNonceAllocationEvent: try PrivateDeploymentEvent
                .decodeRecoveryBytes(nonceAllocation),
            manifestProposalEvent: try PrivateDeploymentEvent
                .decodeRecoveryBytes(proposal),
            manifestSignatureEvents: try signatures.map(
                PrivateDeploymentEvent.decodeRecoveryBytes
            ),
            completeManifestDocument: completeManifest
        )
        guard proof.canonicalDocuments == canonicalDocuments else {
            throw Failure.invalidPrivateDeploymentProof
        }
        return proof
    }
}
#endif
