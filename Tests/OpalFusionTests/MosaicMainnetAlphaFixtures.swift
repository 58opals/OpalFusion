// MosaicMainnetAlphaFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

enum MosaicMainnetAlphaFixtures {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    struct MaterializedPreparation {
        let prepared: MosaicUnsignedTransactionTranscriptFixtures.Prepared
        let materials: [Attempt.ControlIdentity: Alpha.LocalContributionMaterial]
    }

    static let roundIdentifier = [UInt8](repeating: 0x71, count: 32)
    static let transcriptRoot = [UInt8](repeating: 0x72, count: 32)

    enum FixtureError: Error {
        case rsaVerificationKeyUnavailable
        case authorizationEvaluatorUnavailable
    }

    private static let authorizationEvaluatorGenerationLock = NSLock()

    private static let authorizationEvaluatorFixture =
        generateAuthorizationEvaluator()

    private static let bchSignatureAuthorizationEvaluatorFixture =
        generateAuthorizationEvaluator()

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

    private static let bchSignatureRSAVerificationKeyFixture:
        OpalCrypto.RSABSSA.VerificationKey? = {
            let hexadecimal = [
                "30820152303d06092a864886f70d01010a3030a00d300b0609608648016503040202",
                "a11a301806092a864886f70d010108300b0609608648016503040202a20302013003",
                "82010f003082010a0282010100d202a569908b1f229b11568da15f9efb1e7ab2f1",
                "9e29845caf7c845796ac6db84676b751e459c82fd5277484ab13a755cdded61187c",
                "bdd690e1de093453bfb08b297e115fb7f2f7c2e9a2d87f3539f3cc9abe8103eb4",
                "018493378d6291b52dfdb8069bc1d2512aa625b9305ba39e7ed664121eeb6b759",
                "5a4b67a047a3d05e0637661a6a8047755fbabd920ae3691527eb116a9f4ff08162",
                "02da8b09206068cde3dfe0abe13a2c90d269a1d26f06778c8bed4db4686f41371",
                "c025c6119724d45ffad00795bf21041b4b2bbbe69776fa392bb26be628f0691d1e",
                "9ef52aec706d01a13040193a43b6bfe8a9c0e9b7644835cd07423d88645c53feb",
                "05092aae429af0203010001",
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
        guard let authorizationEvaluator = authorizationEvaluatorFixture else {
            throw FixtureError.authorizationEvaluatorUnavailable
        }
        return authorizationEvaluator
    }

    static func bchSignatureAuthorizationEvaluator() throws
        -> OpalV0.AuthorizationEvaluator {
        guard let evaluator = bchSignatureAuthorizationEvaluatorFixture else {
            throw FixtureError.authorizationEvaluatorUnavailable
        }
        return evaluator
    }

    static func requireAuthorizationEvaluators() throws {
        // Acquire both real, purpose-separated fixtures during suite setup.
        // Some suites perform several minutes of deterministic work before
        // their first blind-authorization assertion, and Security.framework
        // can transiently decline deferred RSA generation in a loaded host.
        _ = try authorizationEvaluator()
        _ = try bchSignatureAuthorizationEvaluator()
    }

    private static func generateAuthorizationEvaluator()
        -> OpalV0.AuthorizationEvaluator? {
        authorizationEvaluatorGenerationLock.lock()
        defer { authorizationEvaluatorGenerationLock.unlock() }
        // Security.framework can transiently decline nonpersistent RSA key
        // generation under a heavily loaded test host. Serialize the two lazy
        // purpose fixtures and retry within a fixed bound while preserving the
        // real OpalCrypto key-generation and blind-signing path. The future
        // production attempt-material owner must enforce freshness.
        for _ in 0 ..< 3 {
            if let evaluator = try? OpalV0.AuthorizationEvaluator.generate() {
                return evaluator
            }
        }
        return nil
    }

    static func rsaVerificationKey() throws
        -> OpalCrypto.RSABSSA.VerificationKey {
        guard let verificationKey = rsaVerificationKeyFixture else {
            throw FixtureError.rsaVerificationKeyUnavailable
        }
        return verificationKey
    }

    static func bchSignatureRSAVerificationKey() throws
        -> OpalCrypto.RSABSSA.VerificationKey {
        guard let verificationKey = bchSignatureRSAVerificationKeyFixture else {
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
        bchSignatureVerificationKey:
            OpalCrypto.RSABSSA.VerificationKey? = nil,
        relaySetDigest: [UInt8] = [UInt8](repeating: 0x44, count: 32)
    ) throws -> Alpha.RoundManifestCore {
        try .init(
            candidateSetDigest: [UInt8](repeating: 0x41, count: 32),
            roleElection: election.result,
            opaquePoolIdentifier: [UInt8](repeating: 0x42, count: 32),
            componentAuthorizationVerificationKey: verificationKey,
            bchSignatureAuthorizationVerificationKey:
                try bchSignatureVerificationKey
                    ?? bchSignatureRSAVerificationKey(),
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
        bchSignatureVerificationKey:
            OpalCrypto.RSABSSA.VerificationKey? = nil,
        relaySetDigest: [UInt8] = [UInt8](repeating: 0x44, count: 32)
    ) throws -> Alpha.RoundManifest {
        let core = try makeManifestCore(
            election: election,
            verificationKey: verificationKey,
            bchSignatureVerificationKey: bchSignatureVerificationKey,
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

    static func makeMaterializedPreparation(
        election: MosaicRoleElectionFixtures.Election,
        manifest: Alpha.RoundManifest,
        attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
        generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
        localContributor: Attempt.ControlIdentity,
        localMaterialIdentifier:
            OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    ) throws -> MaterializedPreparation {
        let contributors = manifest.core.orderedContributors
        let materials = try contributors.enumerated().map {
            contributorIndex, contributor in
            let materialIdentifier = contributor == localContributor
                ? localMaterialIdentifier
                : OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier(
                    opaqueBytes: MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(52_000 + contributorIndex)
                )
            return try makeLocalContributionMaterial(
                manifest: manifest,
                contributor: contributor,
                contributorIndex: contributorIndex,
                attemptIdentifier: attemptIdentifier,
                generationIdentifier: generationIdentifier,
                materialIdentifier: materialIdentifier
            )
        }
        let commitmentSet = try OpalV0.CommitmentSet(
            profile: .opalMainnetAlpha,
            commitments: materials.flatMap { $0.slots.map(\.commitment) }
        )
        let componentSet = try OpalV0.ComponentSet(
            profile: .opalMainnetAlpha,
            components: materials.flatMap { $0.slots.map(\.component) }
        )
        let commitmentValidation = try Attempt.CommitmentSetValidation(
            profile: .opalMainnetAlpha,
            roster: manifest.core.roster,
            commitmentSet: commitmentSet
        )
        let transcript = try OpalV0.UnsignedTransactionTranscript(
            profile: .opalMainnetAlpha,
            roster: manifest.core.roster,
            manifest: manifest.binding,
            commitmentSet: commitmentValidation,
            componentSet: componentSet
        )
        return .init(
            prepared: .init(
                commitmentSet: commitmentSet,
                componentSet: componentSet,
                commitmentValidation: commitmentValidation,
                transcript: transcript
            ),
            materials: Dictionary(
                uniqueKeysWithValues: materials.map { ($0.contributor, $0) }
            )
        )
    }

    private static func makeLocalContributionMaterial(
        manifest: Alpha.RoundManifest,
        contributor: Attempt.ControlIdentity,
        contributorIndex: Int,
        attemptIdentifier: OpalFusion.Mosaic.LocalAttempt.AttemptIdentifier,
        generationIdentifier: OpalFusion.Mosaic.LocalAttempt.GenerationIdentifier,
        materialIdentifier: OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
    ) throws -> Alpha.LocalContributionMaterial {
        let inputSigningKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: scalarBytes(10_000 + contributorIndex)
        )
        let publicKey = [UInt8](
            inputSigningKey.publicKey.compressedRepresentation
        )
        let lockingScript = [0x76, 0xA9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xAC]
        let requiredShare = try Alpha.ContributionFeePolicy
            .requiredExcessFeeSatoshis(
                for: contributor,
                in: manifest.core.roster
            )
        let inputAmount = UInt64(100_000 + contributorIndex * 1_000)
        let outputAmount = inputAmount - 175 - requiredShare
        let lease = try OpalFusion.Host.MosaicReservationLease(
            reference: .init(
                identifier: UUID(
                    uuid: (
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0,
                        UInt8(contributorIndex + 1)
                    )
                ),
                generation: 1
            ),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes:
                            MosaicUnsignedTransactionTranscriptFixtures
                                .indexedDigest(1_000 + contributorIndex),
                        outpointIndex: UInt32(contributorIndex),
                        amountSatoshis: inputAmount,
                        lockingScriptBytes: lockingScript,
                        publicKey: publicKey
                    )
                ],
                outputs: [
                    .init(
                        lockingScriptBytes: lockingScript,
                        amountSatoshis: outputAmount
                    )
                ]
            )
        )
        let secrets = try (0 ..< Alpha.componentCountPerContributor).map {
            slot in
            let ordinal = contributorIndex * Alpha.componentCountPerContributor
                + slot + 1
            return try Alpha.ComponentSlotSecrets(
                salt: MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                    10_000 + ordinal
                ),
                pedersenNonce: .init(
                    rawRepresentation: scalarBytes(ordinal)
                ),
                communicationPrivateKey: .init(
                    rawRepresentation: scalarBytes(1_000 + ordinal)
                ),
                componentEnvelopePrivateKey: .init(
                    rawRepresentation: scalarBytes(3_000 + ordinal)
                ),
                bchSignatureEnvelopePrivateKey: .init(
                    rawRepresentation: scalarBytes(4_000 + ordinal)
                ),
                componentAuthorizationNonce:
                    MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                        20_000 + ordinal
                    ),
                bchSignatureAuthorizationNonce:
                    MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                        30_000 + ordinal
                    ),
                recipientEventIdentity: [UInt8](
                    try OpalCrypto.Secp256k1.SigningKey(
                        rawRepresentation: scalarBytes(2_000 + ordinal)
                    ).bip340VerificationKey.rawRepresentation
                )
            )
        }
        return try Alpha.LocalContributionMaterial.build(
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            materialIdentifier: materialIdentifier,
            contributor: contributor,
            manifest: manifest,
            reservationLease: lease,
            slotSecrets: secrets
        )
    }

    private static func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }

    static func makeAuthorizationRequests(byteOffset: UInt8 = 0) throws
        -> [OpalV0.AuthorizationRequestPayload] {
        try (0 ..< Alpha.componentCountPerContributor).map { slot in
            try .init(
                slot: slot,
                blindedMessage: OpalCrypto.RSABSSA.BlindedMessage(
                    rawRepresentation: Data(
                        repeating: byteOffset &+ UInt8(slot + 1),
                        count: OpalV0.authorizationMaterialByteCount
                    )
                )
            )
        }
    }

    static func makeAuthorizationToken(
        purpose: Alpha.AuthorizationPurpose,
        binding: [UInt8],
        roundIdentifier: [UInt8] = roundIdentifier,
        keyIdentifier: [UInt8] = [UInt8](repeating: 0x81, count: 32),
        nonce: [UInt8] = [UInt8](repeating: 0x82, count: 32)
    ) throws -> Alpha.AuthorizationToken {
        .init(
            input: try .init(
                roundIdentifier: roundIdentifier,
                keyIdentifier: keyIdentifier,
                purpose: purpose,
                nonce: nonce,
                binding: binding
            ),
            messageRandomizer: try .init(
                rawRepresentation: Data(repeating: 0x83, count: 32)
            ),
            signature: try .init(
                rawRepresentation: Data(
                    repeating: 0x84,
                    count: OpalV0.authorizationMaterialByteCount
                )
            )
        )
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
