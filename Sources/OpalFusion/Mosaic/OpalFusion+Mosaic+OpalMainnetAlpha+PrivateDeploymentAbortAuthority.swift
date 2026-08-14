// OpalFusion+Mosaic+OpalMainnetAlpha+PrivateDeploymentAbortAuthority.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Phase-specific proof of one recognized abort signer and exact reducer context.
    struct PrivateDeploymentAbortAuthority: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case discoveryContextMismatch
            case invalidPhase
            case unrecognizedParticipant
            case invalidSignerIdentity
            case manifestRoundMismatch
            case expiryOverflow
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let context: PrivateDeploymentAbortContext
        let signerRole: PrivateDeploymentNostrSelector.SignerRole
        let signerIdentity: OpalCrypto.Signature.BIP340.VerificationKey
        let expiryUnixSeconds: UInt64

        static func makeDiscoveryAuthority(
            beacon: AvailabilityBeaconDocument,
            opaquePool: OpaquePoolDocument,
            relaySet: RelaySetDocument
        ) throws(ValidationError) -> Self {
            guard beacon.core.opaquePoolIdentifier == opaquePool.opaqueIdentifier,
                  beacon.core.relaySetDigest == relaySet.digest else {
                throw .discoveryContextMismatch
            }
            let epochStart = beacon.core.discoveryEpochStartUnixSeconds
            let context: PrivateDeploymentAbortContext
            do {
                context = try .makeDiscoveryContext(
                    discoveryEpochStartUnixSeconds: epochStart,
                    opaquePool: opaquePool,
                    relaySet: relaySet
                )
            } catch {
                throw .discoveryContextMismatch
            }
            return try make(
                epochStart: epochStart,
                phase: .discovery,
                context: context,
                signerRole: .discovery,
                signerIdentity: beacon.core.discoveryIdentity
            )
        }

        static func makeSelectedDiscoveryAuthority(
            phase: OpalFusion.Mosaic.Attempt.Phase,
            participant: OpalCrypto.Signature.BIP340.VerificationKey,
            candidateSelection: CandidateSelectionValidation
        ) throws(ValidationError) -> Self {
            guard phase == .candidateSetAgreement
                    || phase == .controlRosterAgreement else {
                throw .invalidPhase
            }
            guard candidateSelection.selectedBeacons.contains(where: {
                $0.core.discoveryIdentity == participant
            }) else {
                throw .unrecognizedParticipant
            }
            return try make(
                epochStart:
                    candidateSelection.discoveryEpochStartUnixSeconds,
                phase: phase,
                context: .makeCandidateSetContext(candidateSelection),
                signerRole: .discovery,
                signerIdentity: participant
            )
        }

        static func makeRoleSelectionAuthority(
            participant: OpalFusion.Mosaic.Attempt.ControlIdentity,
            controlRoster: ControlRosterValidation
        ) throws(ValidationError) -> Self {
            guard controlRoster.controlRosterBinding.controlIdentities
                    .contains(participant) else {
                throw .unrecognizedParticipant
            }
            return try make(
                epochStart: controlRoster.discoveryEpochStartUnixSeconds,
                phase: .roleSelection,
                context: .makeControlRosterContext(controlRoster),
                signerRole: .control,
                signerIdentity: verificationKey(for: participant)
            )
        }

        static func makeManifestAgreementAuthority(
            participant: OpalFusion.Mosaic.Attempt.ControlIdentity,
            proposal: PrivateDeploymentManifestProposalValidation
        ) throws(ValidationError) -> Self {
            let manifest = proposal.manifest
            guard manifest.core.roster.controlIdentities.contains(participant) else {
                throw .unrecognizedParticipant
            }
            let role: PrivateDeploymentNostrSelector.SignerRole =
                participant == manifest.core.roster.conductor
                ? .conductor
                : .control
            return try make(
                epochStart: manifest.discoveryEpochStartUnixSeconds,
                phase: .manifestAgreement,
                context: .makeManifestContext(proposal.signatureBinding),
                signerRole: role,
                signerIdentity: verificationKey(for: participant)
            )
        }

        static func makePostManifestAuthority(
            phase: OpalFusion.Mosaic.Attempt.Phase,
            participant: OpalFusion.Mosaic.Attempt.ControlIdentity,
            manifest: PrivateDeploymentManifestValidation,
            roundManifest: RoundManifest
        ) throws(ValidationError) -> Self {
            guard phase == .walletReservation
                    || phase == .groupedCommitment
                    || phase == .anonymousComponentSubmission
                    || phase == .transcriptAgreement
                    || phase == .bchSigning else {
                throw .invalidPhase
            }
            guard roundManifest.core == manifest.core,
                  roundManifest.binding.roundIdentifier
                    == manifest.core.roundIdentifier else {
                throw .manifestRoundMismatch
            }
            guard manifest.core.roster.controlIdentities.contains(participant) else {
                throw .unrecognizedParticipant
            }
            let role: PrivateDeploymentNostrSelector.SignerRole =
                participant == manifest.core.roster.conductor
                ? .conductor
                : .control
            return .init(
                discoveryEpochStartUnixSeconds:
                    manifest.discoveryEpochStartUnixSeconds,
                phase: phase,
                context: .makeManifestContext(roundManifest.binding),
                signerRole: role,
                signerIdentity: try verificationKey(for: participant),
                expiryUnixSeconds: manifest.core.deadlines.bchSigning
            )
        }

        private static func make(
            epochStart: UInt64,
            phase: OpalFusion.Mosaic.Attempt.Phase,
            context: PrivateDeploymentAbortContext,
            signerRole: PrivateDeploymentNostrSelector.SignerRole,
            signerIdentity: OpalCrypto.Signature.BIP340.VerificationKey
        ) throws(ValidationError) -> Self {
            try .init(
                discoveryEpochStartUnixSeconds: epochStart,
                phase: phase,
                context: context,
                signerRole: signerRole,
                signerIdentity: signerIdentity,
                expiryUnixSeconds: epochEnd(from: epochStart)
            )
        }

        private static func epochEnd(
            from epochStart: UInt64
        ) throws(ValidationError) -> UInt64 {
            let result = epochStart.addingReportingOverflow(
                PrivateDeploymentPolicy.frozen.discoveryEpochDurationSeconds
            )
            guard !result.overflow else { throw .expiryOverflow }
            return result.partialValue
        }

        private static func verificationKey(
            for identity: OpalFusion.Mosaic.Attempt.ControlIdentity
        ) throws(ValidationError) -> OpalCrypto.Signature.BIP340.VerificationKey {
            do {
                return try .init(
                    rawRepresentation: Data(identity.validatedBytes)
                )
            } catch {
                throw .invalidSignerIdentity
            }
        }
    }
}
