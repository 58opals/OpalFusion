// OpalFusion+Mosaic+OpalMainnetAlpha+Manifest.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Locally established pre-manifest facts that a decoded proposal must preserve exactly.
    struct ManifestProposalContext: Sendable, Equatable {
        let roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult
        let candidateSetDigest: [UInt8]
        let opaquePoolIdentifier: [UInt8]

        init(
            roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult,
            candidateSetDigest: [UInt8],
            opaquePoolIdentifier: [UInt8]
        ) throws {
            guard roleElection.profile == .opalMainnetAlpha else {
                throw ContractError.unsupportedProfile(roleElection.profile)
            }
            try RoleSeedValidator.validateFixed(
                candidateSetDigest,
                field: .candidateSetDigest
            )
            try RoleSeedValidator.validateFixed(
                opaquePoolIdentifier,
                field: .poolIdentifier,
                byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                    .opaquePoolIdentifierByteCount
            )
            self.roleElection = roleElection
            self.candidateSetDigest = Array(candidateSetDigest)
            self.opaquePoolIdentifier = Array(opaquePoolIdentifier)
        }
    }

    /// Absolute Unix-second boundaries signed into one manifest.
    struct DeadlineSchedule: Sendable, Equatable {
        let phaseStart: UInt64
        let walletReservation: UInt64
        let groupedCommitment: UInt64
        let anonymousComponentSubmission: UInt64
        let transcriptAgreement: UInt64
        let bchSigning: UInt64

        init(
            phaseStart: UInt64,
            walletReservation: UInt64,
            groupedCommitment: UInt64,
            anonymousComponentSubmission: UInt64,
            transcriptAgreement: UInt64,
            bchSigning: UInt64
        ) throws {
            let ordered = [
                phaseStart,
                walletReservation,
                groupedCommitment,
                anonymousComponentSubmission,
                transcriptAgreement,
                bchSigning
            ]
            guard zip(ordered, ordered.dropFirst()).allSatisfy(<) else {
                throw ContractError.invalidDeadlineOrder
            }
            self.phaseStart = phaseStart
            self.walletReservation = walletReservation
            self.groupedCommitment = groupedCommitment
            self.anonymousComponentSubmission = anonymousComponentSubmission
            self.transcriptAgreement = transcriptAgreement
            self.bchSigning = bchSigning
        }
    }

    /// The exact core whose domain-separated digest is signed by every candidate.
    struct RoundManifestCore: Sendable, Equatable {
        let candidateSetDigest: [UInt8]
        let controlRosterDigest: [UInt8]
        let roleSeed: [UInt8]
        let roster: OpalFusion.Mosaic.Attempt.Roster
        let opaquePoolIdentifier: [UInt8]
        let blindSigningVerificationKey: OpalCrypto.RSABSSA.VerificationKey
        let contributorNonceAllocationDigest: [UInt8]
        let relaySetDigest: [UInt8]
        let deadlines: DeadlineSchedule

        var protocolIdentifier: String {
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
        }

        var networkGenesisHash: [UInt8] {
            OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash
        }

        var transportProfileIdentifier: String {
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.transportProfile.rawValue
        }

        var transactionProfileIdentifier: String {
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.transactionProfileIdentifier
        }

        var componentCount: UInt8 {
            UInt8(OpalFusion.Mosaic.OpalMainnetAlpha.componentCountPerContributor)
        }

        var feeRateSatoshisPerByte: UInt64 {
            OpalFusion.Mosaic.OpalMainnetAlpha.feeRateSatoshisPerByte
        }

        var minimumExcessFeeSatoshis: UInt64 {
            OpalFusion.Mosaic.OpalMainnetAlpha.minimumExcessFeeSatoshis
        }

        var maximumExcessFeeSatoshis: UInt64 {
            OpalFusion.Mosaic.OpalMainnetAlpha.maximumExcessFeeSatoshis
        }

        var sortedRosterMembers: [OpalFusion.Mosaic.Attempt.RosterMember] {
            roster.members.sorted {
                $0.controlIdentity.validatedBytes.lexicographicallyPrecedes(
                    $1.controlIdentity.validatedBytes
                )
            }
        }

        var orderedContributors: [OpalFusion.Mosaic.Attempt.ControlIdentity] {
            roster.contributors.sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
        }

        var canonicalBytes: [UInt8] {
            do {
                return try CanonicalWireCodec.encodeManifestCore(self)
            } catch {
                preconditionFailure("A validated mainnet-alpha manifest core must encode.")
            }
        }

        var roundIdentifier: [UInt8] {
            RoleSeedValidator.hash(
                domainSuffix: "manifest",
                fields: [canonicalBytes]
            )
        }

        init(
            candidateSetDigest: [UInt8],
            roleElection: OpalFusion.Mosaic.Attempt.RoleElectionResult,
            opaquePoolIdentifier: [UInt8],
            blindSigningVerificationKey: OpalCrypto.RSABSSA.VerificationKey,
            contributorNonceAllocationDigest: [UInt8],
            relaySetDigest: [UInt8],
            deadlines: DeadlineSchedule
        ) throws {
            guard roleElection.profile == .opalMainnetAlpha else {
                throw ContractError.unsupportedProfile(roleElection.profile)
            }
            try RoleSeedValidator.validateFixed(
                candidateSetDigest,
                field: .candidateSetDigest
            )
            try RoleSeedValidator.validateFixed(
                roleElection.controlRosterDigest,
                field: .controlRosterDigest
            )
            try RoleSeedValidator.validateFixed(
                roleElection.roleSeed,
                field: .roleSeed
            )
            try RoleSeedValidator.validateFixed(
                opaquePoolIdentifier,
                field: .poolIdentifier,
                byteCount: OpalFusion.Mosaic.OpalMainnetAlpha
                    .opaquePoolIdentifierByteCount
            )
            try RoleSeedValidator.validateFixed(
                contributorNonceAllocationDigest,
                field: .nonceAllocationDigest
            )
            try RoleSeedValidator.validateFixed(
                relaySetDigest,
                field: .relaySetDigest
            )
            guard blindSigningVerificationKey.subjectPublicKeyInfo.count
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .blindSigningVerificationKeyByteCount else {
                throw ContractError.invalidBlindSigningKey
            }

            self.candidateSetDigest = Array(candidateSetDigest)
            self.controlRosterDigest = roleElection.controlRosterDigest
            self.roleSeed = roleElection.roleSeed
            self.roster = roleElection.roster
            self.opaquePoolIdentifier = Array(opaquePoolIdentifier)
            self.blindSigningVerificationKey = blindSigningVerificationKey
            self.contributorNonceAllocationDigest = Array(
                contributorNonceAllocationDigest
            )
            self.relaySetDigest = Array(relaySetDigest)
            self.deadlines = deadlines
        }

        func validateProposal(
            against context: ManifestProposalContext
        ) throws {
            guard roster == context.roleElection.roster,
                  controlRosterDigest
                    == context.roleElection.controlRosterDigest,
                  roleSeed == context.roleElection.roleSeed else {
                throw ContractError.rosterMismatch
            }
            guard candidateSetDigest == context.candidateSetDigest else {
                throw ContractError.candidateSetDigestMismatch
            }
            guard opaquePoolIdentifier == context.opaquePoolIdentifier else {
                throw ContractError.poolIdentifierMismatch
            }
        }
    }

    /// A complete manifest with one valid round signature from every roster member.
    struct RoundManifest: Sendable, Equatable {
        let core: RoundManifestCore
        let signatures: [OpalFusion.Mosaic.Attempt.ManifestSignature]
        let binding: OpalFusion.Mosaic.Attempt.ManifestBinding
        let canonicalBytes: [UInt8]

        init(
            core: RoundManifestCore,
            signatures: [OpalFusion.Mosaic.Attempt.ManifestSignature]
        ) throws {
            let expectedCount = core.roster.candidateCount
            guard signatures.count == expectedCount else {
                throw ContractError.invalidManifestSignatureCount(
                    expected: expectedCount,
                    actual: signatures.count
                )
            }
            let expectedSigners = Set(core.roster.controlIdentities)
            var seenSigners: Set<OpalFusion.Mosaic.Attempt.ControlIdentity> = []
            let sortedSignatures = signatures.sorted {
                $0.signer.validatedBytes.lexicographicallyPrecedes(
                    $1.signer.validatedBytes
                )
            }
            for signature in sortedSignatures {
                guard expectedSigners.contains(signature.signer) else {
                    throw ContractError.unknownManifestSigner
                }
                guard seenSigners.insert(signature.signer).inserted else {
                    throw ContractError.duplicateManifestSigner
                }
            }

            let canonicalBytes = try CanonicalWireCodec.encodeManifest(
                core: core,
                signatures: sortedSignatures
            )
            let manifestDigest = RoleSeedValidator.hash(
                domainSuffix: "complete-manifest",
                fields: [canonicalBytes]
            )
            let binding = try OpalFusion.Mosaic.Attempt.ManifestBinding(
                validatedRoundIdentifier: core.roundIdentifier,
                validatedManifestDigest: manifestDigest
            )
            let validations: [OpalFusion.Mosaic.Attempt.ManifestSignatureValidation]
            do {
                validations = try sortedSignatures.map {
                    try .init(validating: $0, for: binding)
                }
                _ = try OpalFusion.Mosaic.Attempt.ManifestAgreement(
                    roster: core.roster,
                    validatedSignatures: validations
                )
            } catch {
                throw ContractError.invalidManifestSignature
            }

            self.core = core
            self.signatures = sortedSignatures
            self.binding = binding
            self.canonicalBytes = canonicalBytes
        }
    }
}

extension OpalFusion.Mosaic.Role {
    var mainnetAlphaCanonicalValue: UInt8 {
        switch self {
        case .conductor: 0
        case .contributor: 1
        }
    }

    init(mainnetAlphaCanonicalValue: UInt8) throws {
        switch mainnetAlphaCanonicalValue {
        case 0: self = .conductor
        case 1: self = .contributor
        default:
            throw OpalFusion.Mosaic.OpalMainnetAlpha.ContractError.invalidRole(
                mainnetAlphaCanonicalValue
            )
        }
    }
}
