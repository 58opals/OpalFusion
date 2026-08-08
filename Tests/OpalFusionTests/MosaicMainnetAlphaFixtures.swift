// MosaicMainnetAlphaFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

enum MosaicMainnetAlphaFixtures {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    static let roundIdentifier = [UInt8](repeating: 0x71, count: 32)
    static let transcriptRoot = [UInt8](repeating: 0x72, count: 32)

    static func scalarByte(
        for identity: Attempt.ControlIdentity
    ) -> UInt8? {
        (1 ... 10).compactMap(UInt8.init).first {
            MosaicManifestSignatureFixtures.controlIdentity(
                scalarByte: $0
            ) == identity
        }
    }

    static func makeElection(candidateCount: Int = 7) throws
        -> MosaicRoleElectionFixtures.Election {
        let identities = (1 ... candidateCount).map {
            MosaicManifestSignatureFixtures.controlIdentity(
                scalarByte: UInt8($0)
            )
        }
        let controlRoster = try Attempt.ControlRosterBinding(
            validatedControlIdentities: identities,
            validatedControlRosterDigest: [UInt8](repeating: 0x31, count: 32)
        )
        let reveals = controlRoster.controlIdentities.enumerated().map {
            index, identity in
            Attempt.RoleReveal(
                candidate: identity,
                controlRosterDigest: controlRoster.controlRosterDigest,
                randomness: [UInt8](repeating: UInt8(index + 1), count: 32)
            )
        }
        let commitments = try reveals.map { reveal in
            Attempt.RoleCommitment(
                candidate: reveal.candidate,
                controlRosterDigest: controlRoster.controlRosterDigest,
                commitment: try Alpha.RoleSeedValidator.roleCommitment(
                    controlRosterDigest: controlRoster.controlRosterDigest,
                    controlIdentity: reveal.candidate,
                    randomness: reveal.randomness
                )
            )
        }
        let commitmentSet = try Attempt.RoleCommitmentSet(
            controlRoster: controlRoster,
            commitments: commitments
        )
        let validation = try Attempt.RoleSeedValidation(
            profile: .opalMainnetAlpha,
            commitmentSet: commitmentSet,
            reveals: reveals,
            using: Alpha.RoleSeedValidator()
        )
        let result = try Attempt.RoleElectionResult(
            profile: .opalMainnetAlpha,
            commitmentSet: commitmentSet,
            validation: validation
        )
        return .init(
            controlRoster: controlRoster,
            commitments: commitments,
            commitmentSet: commitmentSet,
            reveals: reveals,
            validation: validation,
            result: result
        )
    }

    static func makeManifestCore(
        election: MosaicRoleElectionFixtures.Election,
        verificationKey: OpalCrypto.RSABSSA.VerificationKey
    ) throws -> Alpha.RoundManifestCore {
        try .init(
            candidateSetDigest: [UInt8](repeating: 0x41, count: 32),
            roleElection: election.result,
            opaquePoolIdentifier: [UInt8](repeating: 0x42, count: 32),
            blindSigningVerificationKey: verificationKey,
            contributorNonceAllocationDigest: [UInt8](
                repeating: 0x43,
                count: 32
            ),
            relaySetDigest: [UInt8](repeating: 0x44, count: 32),
            deadlines: try .init(
                phaseStart: 1_800_000_000,
                walletReservation: 1_800_000_010,
                groupedCommitment: 1_800_000_020,
                anonymousComponentSubmission: 1_800_000_030,
                transcriptAgreement: 1_800_000_040,
                bchSigning: 1_800_000_050
            )
        )
    }

    static func makeManifestProposalContext(
        election: MosaicRoleElectionFixtures.Election
    ) throws -> Alpha.ManifestProposalContext {
        try .init(
            roleElection: election.result,
            candidateSetDigest: [UInt8](repeating: 0x41, count: 32),
            opaquePoolIdentifier: [UInt8](repeating: 0x42, count: 32)
        )
    }

    static func makeManifest(
        election: MosaicRoleElectionFixtures.Election,
        verificationKey: OpalCrypto.RSABSSA.VerificationKey
    ) throws -> Alpha.RoundManifest {
        let core = try makeManifestCore(
            election: election,
            verificationKey: verificationKey
        )
        let temporaryBinding = try Attempt.ManifestBinding(
            validatedRoundIdentifier: core.roundIdentifier,
            validatedManifestDigest: [UInt8](repeating: 0, count: 32)
        )
        return try .init(
            core: core,
            signatures: MosaicManifestSignatureFixtures.manifestSignatures(
                for: election.result.roster,
                binding: temporaryBinding
            )
        )
    }

    static func makeAuthorizationRequests() throws
        -> [OpalV0.AuthorizationRequestPayload] {
        try (0 ..< Alpha.componentCountPerContributor).map { slot in
            try .init(
                slot: slot,
                blindedMessage: OpalCrypto.RSABSSA.BlindedMessage(
                    rawRepresentation: Data(
                        repeating: UInt8(slot + 1),
                        count: OpalV0.authorizationMaterialByteCount
                    )
                )
            )
        }
    }

    static func signControlEnvelope(
        scalarByte: UInt8,
        senderEventIdentity: [UInt8],
        phase: Attempt.Phase,
        payloadType: Alpha.ControlPayloadType,
        payload: [UInt8],
        sequence: UInt64 = 0
    ) throws -> Alpha.ControlEnvelope {
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
        let sender = Attempt.ControlIdentity(
            validatedBytes: [UInt8](
                signingKey.bip340VerificationKey.rawRepresentation
            )
        )
        let digest = try Alpha.ControlEnvelope.signingDigest(
            roundIdentifier: roundIdentifier,
            phase: phase,
            senderControlIdentity: sender,
            senderEventIdentity: senderEventIdentity,
            sequence: sequence,
            payloadType: payloadType,
            expiryUnixSeconds: 1_800_000_060,
            payload: payload
        )
        let signature = try signingKey.signBIP340(
            digest: OpalCrypto.Signature.Digest(
                rawRepresentation: Data(digest)
            ),
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0xA5, count: 32)
            )
        )
        return try .init(
            roundIdentifier: roundIdentifier,
            phase: phase,
            senderControlIdentity: sender,
            senderEventIdentity: senderEventIdentity,
            sequence: sequence,
            payloadType: payloadType,
            expiryUnixSeconds: 1_800_000_060,
            controlSignature: [UInt8](signature.rawRepresentation),
            payload: payload
        )
    }
}
