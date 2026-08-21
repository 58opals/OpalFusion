// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentAbortAuthority.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    static func preManifestTimeoutBoundary(
        phase: Phase,
        discoveryEpochStartUnixSeconds: UInt64
    ) throws -> UInt64 {
        let deadlines = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentPolicy.frozen.preManifestDeadlines(
                forEpochStartingAt: discoveryEpochStartUnixSeconds
            )
        switch phase {
        case .discovery:
            return deadlines.beaconCutoff
        case .candidateSetAgreement:
            return deadlines.candidateSetAgreement
        case .admission:
            return deadlines.controlRosterAgreement
        case .controlRosterAgreement:
            return deadlines.roleCommitment
        case .roleElection:
            return deadlines.roleReveal
        case .nonceAllocation, .manifestAgreement:
            return deadlines.manifestAgreement
        case .walletReservation, .groupedCommitment,
             .anonymousComponentSubmission, .transcriptAgreement, .bchSigning:
            throw Failure.invalidStateTransition
        }
    }

    static func privateDeploymentAbortAuthority(
        formation: PrivateDeploymentFormationState,
        signerIdentity: OpalCrypto.Signature.BIP340.VerificationKey
    ) throws -> OpalFusion.Mosaic.OpalMainnetAlpha
        .PrivateDeploymentAbortAuthority {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Attempt = OpalFusion.Mosaic.Attempt
        let controlIdentity = Attempt.ControlIdentity(
            validatedBytes: [UInt8](signerIdentity.rawRepresentation)
        )
        switch formation {
        case let .discovery(pool, relaySet, _, beacons):
            guard let beacon = beacons.first(where: {
                $0.core.discoveryIdentity == signerIdentity
            }) else {
                throw Failure.invalidStateTransition
            }
            return try .makeDiscoveryAuthority(
                beacon: beacon,
                opaquePool: pool,
                relaySet: relaySet
            )
        case let .candidateSetAgreement(selection, _, _):
            return try .makeSelectedDiscoveryAuthority(
                phase: .candidateSetAgreement,
                participant: signerIdentity,
                candidateSelection: selection
            )
        case let .admission(selection, _, _, _):
            return try .makeSelectedDiscoveryAuthority(
                phase: .controlRosterAgreement,
                participant: signerIdentity,
                candidateSelection: selection
            )
        case let .controlRosterAgreement(_, controlRoster, _, _),
             let .roleElection(_, controlRoster, _, _, _),
             let .nonceAllocationPending(_, controlRoster, _),
             let .nonceAllocationAccepted(_, controlRoster, _, _),
             let .manifestProposalPending(
                _, _, _, controlRoster, _, _
             ):
            return try .makeRoleSelectionAuthority(
                participant: controlIdentity,
                controlRoster: controlRoster
            )
        case let .manifestSignatures(proposal, _, _):
            return try .makeManifestAgreementAuthority(
                participant: controlIdentity,
                proposal: proposal
            )
        case .uninitialized:
            throw Failure.invalidStateTransition
        }
    }
}
#endif
