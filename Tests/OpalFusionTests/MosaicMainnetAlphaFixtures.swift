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

    enum FixtureError: Error {
        case rsaVerificationKeyUnavailable
        case authorizationEvaluatorUnavailable
    }

    private static let authorizationEvaluatorFixture: OpalV0.AuthorizationEvaluator?
        = {
            // Security.framework can transiently decline nonpersistent RSA key
            // generation under a heavily loaded test host. Keep the fixture
            // test-process-scoped, bounded, and lazy while preserving the real
            // OpalCrypto key-generation and blind-signing path. The future
            // production attempt-material owner must enforce key freshness.
            for _ in 0 ..< 3 {
                if let evaluator = try? OpalV0.AuthorizationEvaluator.generate() {
                    return evaluator
                }
            }
            return nil
        }()

    private static let rsaVerificationKeyFixture: OpalCrypto.RSABSSA.VerificationKey?
        = {
            let hexadecimal = [
                "30820152303d06092a864886f70d01010a3030a00d300b0609608648016503040202",
                "a11a301806092a864886f70d010108300b0609608648016503040202a20302013003",
                "82010f003082010a0282010100decc4d1709d10fa18365e80fdb0600f56758d95f",
                "6df541ad09635130fd588b1244831223b9c183591f2b6047e6ad05d19dda9b12695f",
                "6cb290b8f86ad10aa96ca45fea2b0d2a3ad44d09ca2a8aac0c25b726849c5e127",
                "c1ea3dd59875ea88e6570449b90d66e5263ced23971205111b9d72e4bb35e9703b",
                "58a346e4c6a732bd92b5d2aedf13203b2eb1eab9c4e401686bed5836d2ab891cc7",
                "e727b92480ce406ae4f76d2219931d028fde4dce987458c79d224d36366cdc97703",
                "4db2ea0e0a4acdc29baf8f0dbca6c98e3192726e2e95aab9ab1e89ae6fe674918",
                "9bdb663d8aba58f4008bd3bbfda7a8a0048d00362b5436335be3d51b3f8271589",
                "7ee03124f50203010001",
            ].joined()
            return try? .init(
                subjectPublicKeyInfo: Data(
                    MosaicOpalV0WireContractValidator.bytes(
                        hexadecimal: hexadecimal
                    )
                )
            )
        }()

    static func authorizationEvaluator() throws
        -> OpalV0.AuthorizationEvaluator {
        guard let authorizationEvaluator = authorizationEvaluatorFixture
        else {
            throw FixtureError.authorizationEvaluatorUnavailable
        }
        return authorizationEvaluator
    }

    static func rsaVerificationKey() throws
        -> OpalCrypto.RSABSSA.VerificationKey {
        guard let verificationKey = rsaVerificationKeyFixture else {
            throw FixtureError.rsaVerificationKeyUnavailable
        }
        return verificationKey
    }

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
        verificationKey: OpalCrypto.RSABSSA.VerificationKey,
        relaySetDigest: [UInt8] = [UInt8](repeating: 0x44, count: 32)
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
            relaySetDigest: relaySetDigest,
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
        verificationKey: OpalCrypto.RSABSSA.VerificationKey,
        relaySetDigest: [UInt8] = [UInt8](repeating: 0x44, count: 32)
    ) throws -> Alpha.RoundManifest {
        let core = try makeManifestCore(
            election: election,
            verificationKey: verificationKey,
            relaySetDigest: relaySetDigest
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
        sequence: UInt64 = 0,
        roundIdentifier: [UInt8] = MosaicMainnetAlphaFixtures.roundIdentifier,
        expiryUnixSeconds: UInt64 = 1_800_000_060
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
            expiryUnixSeconds: expiryUnixSeconds,
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
            expiryUnixSeconds: expiryUnixSeconds,
            controlSignature: [UInt8](signature.rawRepresentation),
            payload: payload
        )
    }
}
