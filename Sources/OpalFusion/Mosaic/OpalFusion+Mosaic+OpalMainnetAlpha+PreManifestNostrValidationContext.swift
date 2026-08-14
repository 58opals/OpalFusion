// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestNostrValidationContext.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Proof-derived authority and receiver clock facts for one coordination event.
    struct PreManifestNostrValidationContext: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidDiscoveryEpoch
            case invalidExpectedExpiry
            case unrecognizedSigner
            case roleElectionMismatch
            case invalidSignerIdentity
        }

        let discoveryEpochStartUnixSeconds: UInt64
        let expectedSignerRole: PrivateDeploymentNostrSelector.SignerRole
        let expectedSignerIdentity: OpalCrypto.Signature.BIP340.VerificationKey
        let expectedExpiryUnixSeconds: UInt64
        let currentUnixSeconds: UInt64

        private init(
            discoveryEpochStartUnixSeconds: UInt64,
            expectedSignerRole: PrivateDeploymentNostrSelector.SignerRole,
            expectedSignerIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            expectedExpiryUnixSeconds: UInt64,
            currentUnixSeconds: UInt64
        ) throws(ValidationError) {
            do {
                try PrivateDeploymentPolicy.frozen.validate(
                    epochStart: discoveryEpochStartUnixSeconds
                )
            } catch {
                throw .invalidDiscoveryEpoch
            }
            guard expectedExpiryUnixSeconds > discoveryEpochStartUnixSeconds else {
                throw .invalidExpectedExpiry
            }
            self.discoveryEpochStartUnixSeconds = discoveryEpochStartUnixSeconds
            self.expectedSignerRole = expectedSignerRole
            self.expectedSignerIdentity = expectedSignerIdentity
            self.expectedExpiryUnixSeconds = expectedExpiryUnixSeconds
            self.currentUnixSeconds = currentUnixSeconds
        }

        static func makeDiscoveryContext(
            discoveryEpochStartUnixSeconds: UInt64,
            discoveryIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            payloadKind: PrivateDeploymentNostrSelector.PayloadKind,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            guard payloadKind == .availabilityBeacon
                    || payloadKind == .candidateSetAcknowledgement
                    || payloadKind == .candidateAdmission else {
                throw ValidationError.unrecognizedSigner
            }
            return try makePreManifestContext(
                epochStart: discoveryEpochStartUnixSeconds,
                signerRole: .discovery,
                signerIdentity: discoveryIdentity,
                payloadKind: payloadKind,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        static func makeRoleContext(
            signer: OpalFusion.Mosaic.Attempt.ControlIdentity,
            payloadKind: PrivateDeploymentNostrSelector.PayloadKind,
            controlRoster: ControlRosterValidation,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            guard payloadKind == .roleCommitment || payloadKind == .roleReveal,
                  controlRoster.controlRosterBinding.controlIdentities
                    .contains(signer) else {
                throw ValidationError.unrecognizedSigner
            }
            return try makePreManifestContext(
                epochStart: controlRoster.discoveryEpochStartUnixSeconds,
                signerRole: .control,
                signerIdentity: verificationKey(for: signer),
                payloadKind: payloadKind,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        static func makeManifestProposalContext(
            proposal: PrivateDeploymentManifestProposalValidation,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            try makePreManifestContext(
                epochStart: proposal.manifest.discoveryEpochStartUnixSeconds,
                signerRole: .conductor,
                signerIdentity: verificationKey(
                    for: proposal.manifest.core.roster.conductor
                ),
                payloadKind: .manifestProposal,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        static func makeManifestSignatureContext(
            signer: OpalFusion.Mosaic.Attempt.ControlIdentity,
            proposal: PrivateDeploymentManifestProposalValidation,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            let roster = proposal.manifest.core.roster
            guard roster.controlIdentities.contains(signer) else {
                throw ValidationError.unrecognizedSigner
            }
            return try makePreManifestContext(
                epochStart: proposal.manifest.discoveryEpochStartUnixSeconds,
                signerRole: signer == roster.conductor ? .conductor : .control,
                signerIdentity: verificationKey(for: signer),
                payloadKind: .manifestSignature,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        static func makeContributorNonceAllocationContext(
            controlRoster: ControlRosterValidation,
            roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            try requireMatchingRoleElection(
                roleElection,
                controlRoster: controlRoster
            )
            return try makePreManifestContext(
                epochStart: controlRoster.discoveryEpochStartUnixSeconds,
                signerRole: .conductor,
                signerIdentity: verificationKey(
                    for: roleElection.roster.conductor
                ),
                payloadKind: .contributorNonceAllocation,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        static func makeAbortContext(
            authority: PrivateDeploymentAbortAuthority,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            try .init(
                discoveryEpochStartUnixSeconds:
                    authority.discoveryEpochStartUnixSeconds,
                expectedSignerRole: authority.signerRole,
                expectedSignerIdentity: authority.signerIdentity,
                expectedExpiryUnixSeconds: authority.expiryUnixSeconds,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        static func makeCompletionContext(
            validation: PrivateDeploymentCompletionValidation,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            try .init(
                discoveryEpochStartUnixSeconds:
                    validation.manifest.discoveryEpochStartUnixSeconds,
                expectedSignerRole: .conductor,
                expectedSignerIdentity: verificationKey(
                    for: validation.roundManifest.core.roster.conductor
                ),
                expectedExpiryUnixSeconds:
                    validation.roundManifest.core.deadlines.bchSigning,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        private static func makePreManifestContext(
            epochStart: UInt64,
            signerRole: PrivateDeploymentNostrSelector.SignerRole,
            signerIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
            payloadKind: PrivateDeploymentNostrSelector.PayloadKind,
            currentUnixSeconds: UInt64
        ) throws -> Self {
            let deadlines = try PrivateDeploymentPolicy.frozen
                .preManifestDeadlines(forEpochStartingAt: epochStart)
            let expiry: UInt64
            switch payloadKind {
            case .availabilityBeacon: expiry = deadlines.beaconCutoff
            case .candidateSetAcknowledgement:
                expiry = deadlines.candidateSetAgreement
            case .candidateAdmission: expiry = deadlines.controlRosterAgreement
            case .roleCommitment: expiry = deadlines.roleCommitment
            case .roleReveal: expiry = deadlines.roleReveal
            case .contributorNonceAllocation,
                 .manifestProposal,
                 .manifestSignature:
                expiry = deadlines.manifestAgreement
            case .abort, .completion:
                throw ValidationError.invalidExpectedExpiry
            }
            return try .init(
                discoveryEpochStartUnixSeconds: epochStart,
                expectedSignerRole: signerRole,
                expectedSignerIdentity: signerIdentity,
                expectedExpiryUnixSeconds: expiry,
                currentUnixSeconds: currentUnixSeconds
            )
        }

        private static func requireMatchingRoleElection(
            _ roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult,
            controlRoster: ControlRosterValidation
        ) throws {
            let expected = Set(
                controlRoster.controlRosterBinding.controlIdentities.map {
                    $0.validatedBytes
                }
            )
            let actual = Set(
                roleElection.roster.controlIdentities.map(\.validatedBytes)
            )
            guard roleElection.controlRosterDigest
                    == controlRoster.controlRosterDigest,
                  expected == actual else {
                throw ValidationError.roleElectionMismatch
            }
        }

        private static func verificationKey(
            for identity: OpalFusion.Mosaic.Attempt.ControlIdentity
        ) throws -> OpalCrypto.Signature.BIP340.VerificationKey {
            do {
                return try .init(
                    rawRepresentation: Data(identity.validatedBytes)
                )
            } catch {
                throw ValidationError.invalidSignerIdentity
            }
        }
    }
}
