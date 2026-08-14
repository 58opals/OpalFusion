// OpalFusion+Mosaic+OpalMainnetAlpha+PreManifestNostrPayloadDocument~Factory.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestNostrPayloadDocument {
    static func makeAvailabilityBeacon(
        _ document: OpalFusion.Mosaic.OpalMainnetAlpha.AvailabilityBeaconDocument
    ) throws -> Self {
        try make(
            epochStart: document.core.discoveryEpochStartUnixSeconds,
            payloadKind: .availabilityBeacon,
            signerRole: .discovery,
            signerIdentity: document.core.discoveryIdentity,
            body: document.canonicalBytes
        )
    }

    static func makeCandidateSetAcknowledgement(
        _ document: OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateSetAcknowledgementDocument
    ) throws -> Self {
        try make(
            epochStart: document.discoveryEpochStartUnixSeconds,
            payloadKind: .candidateSetAcknowledgement,
            signerRole: .discovery,
            signerIdentity: document.signerDiscoveryIdentity,
            body: document.canonicalBytes
        )
    }

    static func makeCandidateAdmission(
        _ document: OpalFusion.Mosaic.OpalMainnetAlpha.CandidateAdmissionDocument
    ) throws -> Self {
        try make(
            epochStart: document.discoveryEpochStartUnixSeconds,
            payloadKind: .candidateAdmission,
            signerRole: .discovery,
            signerIdentity: document.discoveryIdentity,
            body: document.canonicalBytes
        )
    }

    static func makeRoleCommitment(
        _ commitment: OpalFusion.Mosaic.Attempt.RoleCommitment,
        controlRoster: OpalFusion.Mosaic.OpalMainnetAlpha
            .ControlRosterValidation
    ) throws -> Self {
        let body = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.encodeRoleCommitment(commitment)
        guard try OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestDocumentCodec
                .decodeRoleCommitment(
                    from: body,
                    controlRoster: controlRoster.controlRosterBinding
                ) == commitment else {
            throw ValidationError.authorityMismatch
        }
        return try make(
            epochStart: controlRoster.discoveryEpochStartUnixSeconds,
            payloadKind: .roleCommitment,
            signerRole: .control,
            signerIdentity: verificationKey(for: commitment.candidate),
            body: body
        )
    }

    static func makeRoleReveal(
        _ reveal: OpalFusion.Mosaic.Attempt.RoleReveal,
        controlRoster: OpalFusion.Mosaic.OpalMainnetAlpha
            .ControlRosterValidation
    ) throws -> Self {
        let body = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.encodeRoleReveal(reveal)
        guard try OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestDocumentCodec
                .decodeRoleReveal(
                    from: body,
                    controlRoster: controlRoster.controlRosterBinding
                ) == reveal else {
            throw ValidationError.authorityMismatch
        }
        return try make(
            epochStart: controlRoster.discoveryEpochStartUnixSeconds,
            payloadKind: .roleReveal,
            signerRole: .control,
            signerIdentity: verificationKey(for: reveal.candidate),
            body: body
        )
    }

    static func makeManifestProposal(
        _ proposal: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestProposalValidation
    ) throws -> Self {
        try make(
            epochStart: proposal.manifest.discoveryEpochStartUnixSeconds,
            payloadKind: .manifestProposal,
            signerRole: .conductor,
            signerIdentity: verificationKey(
                for: proposal.manifest.core.roster.conductor
            ),
            body: proposal.canonicalBody
        )
    }

    static func makeManifestSignature(
        _ signature: OpalFusion.Mosaic.Attempt.ManifestSignature,
        proposal: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestProposalValidation
    ) throws -> Self {
        let roster = proposal.manifest.core.roster
        guard roster.controlIdentities.contains(signature.signer) else {
            throw ValidationError.signerNotInRoster
        }
        let body = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestDocumentCodec.encodeManifestSignature(signature)
        _ = try OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestDocumentCodec
            .decodeManifestSignature(
                from: body,
                for: proposal.signatureBinding,
                expectedRoster: roster
            )
        let signerRole: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentNostrSelector.SignerRole =
            signature.signer == roster.conductor ? .conductor : .control
        return try make(
            epochStart: proposal.manifest.discoveryEpochStartUnixSeconds,
            payloadKind: .manifestSignature,
            signerRole: signerRole,
            signerIdentity: verificationKey(for: signature.signer),
            body: body
        )
    }

    static func makeContributorNonceAllocation(
        _ document: OpalFusion.Mosaic.OpalMainnetAlpha
            .ContributorNonceAllocationDocument,
        controlRoster: OpalFusion.Mosaic.OpalMainnetAlpha
            .ControlRosterValidation,
        roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult
    ) throws -> Self {
        let expectedRoster = Set(
            controlRoster.controlRosterBinding.controlIdentities.map {
                Data($0.validatedBytes)
            }
        )
        let actualRoster = Set(
            roleElection.roster.controlIdentities.map {
                Data($0.validatedBytes)
            }
        )
        guard roleElection.controlRosterDigest
                == controlRoster.controlRosterDigest,
              expectedRoster == actualRoster else {
            throw ValidationError.authorityMismatch
        }
        _ = try OpalFusion.Mosaic.OpalMainnetAlpha
            .ContributorNonceAllocationDocument.decode(
                from: document.canonicalBytes,
                roleElection: roleElection
        )
        return try make(
            epochStart: controlRoster.discoveryEpochStartUnixSeconds,
            payloadKind: .contributorNonceAllocation,
            signerRole: .conductor,
            signerIdentity: verificationKey(for: roleElection.roster.conductor),
            body: document.canonicalBytes
        )
    }

    static func makeAbort(
        _ document: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentAbortDocument,
        authority: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentAbortAuthority
    ) throws -> Self {
        guard document.discoveryEpochStartUnixSeconds
                == authority.discoveryEpochStartUnixSeconds,
              document.phase == authority.phase,
              document.context == authority.context else {
            throw ValidationError.authorityMismatch
        }
        return try .init(
            discoveryEpochStartUnixSeconds:
                document.discoveryEpochStartUnixSeconds,
            payloadKind: .abort,
            signerRole: authority.signerRole,
            signerIdentity: authority.signerIdentity,
            expiryUnixSeconds: authority.expiryUnixSeconds,
            body: document.canonicalBytes
        )
    }

    static func makeCompletion(
        _ document: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentCompletionDocument,
        validation: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentCompletionValidation
    ) throws -> Self {
        guard document.discoveryEpochStartUnixSeconds
                == validation.manifest.discoveryEpochStartUnixSeconds,
              document.roundIdentifier
                == validation.roundManifest.core.roundIdentifier,
              document.completeTransactionDigest
                == validation.completedPayload.digest else {
            throw ValidationError.authorityMismatch
        }
        return try .init(
            discoveryEpochStartUnixSeconds:
                document.discoveryEpochStartUnixSeconds,
            payloadKind: .completion,
            signerRole: .conductor,
            signerIdentity: verificationKey(
                for: validation.roundManifest.core.roster.conductor
            ),
            expiryUnixSeconds:
                validation.roundManifest.core.deadlines.bchSigning,
            body: document.canonicalBytes
        )
    }

    private static func make(
        epochStart: UInt64,
        payloadKind: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentNostrSelector.PayloadKind,
        signerRole: OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentNostrSelector.SignerRole,
        signerIdentity: OpalCrypto.Signature.BIP340.VerificationKey,
        body: [UInt8]
    ) throws -> Self {
        let deadlines = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentPolicy.frozen.preManifestDeadlines(
                forEpochStartingAt: epochStart
            )
        let expiry: UInt64
        switch payloadKind {
        case .availabilityBeacon: expiry = deadlines.beaconCutoff
        case .candidateSetAcknowledgement:
            expiry = deadlines.candidateSetAgreement
        case .candidateAdmission: expiry = deadlines.controlRosterAgreement
        case .roleCommitment: expiry = deadlines.roleCommitment
        case .roleReveal: expiry = deadlines.roleReveal
        case .contributorNonceAllocation:
            expiry = deadlines.manifestAgreement
        case .manifestProposal, .manifestSignature:
            expiry = deadlines.manifestAgreement
        case .abort, .completion:
            preconditionFailure("Terminal payloads carry caller-owned expiry.")
        }
        return try .init(
            discoveryEpochStartUnixSeconds: epochStart,
            payloadKind: payloadKind,
            signerRole: signerRole,
            signerIdentity: signerIdentity,
            expiryUnixSeconds: expiry,
            body: body
        )
    }

    private static func verificationKey(
        for identity: OpalFusion.Mosaic.Attempt.ControlIdentity
    ) throws -> OpalCrypto.Signature.BIP340.VerificationKey {
        try .init(rawRepresentation: Data(identity.validatedBytes))
    }
}
