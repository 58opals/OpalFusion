// MosaicSemanticValidator+Fixtures.swift

@testable import OpalFusion

extension MosaicSemanticValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Simulator = MosaicSemanticSimulator

    static let configuration = OpalFusion.Mosaic.Configuration(profile: .opalV0)

    static let manifestA = try! Attempt.ManifestBinding(
        validatedRoundIdentifier: Array(repeating: 0xA1, count: 32),
        validatedManifestDigest: Array(repeating: 0xA2, count: 32)
    )
    static let manifestB = try! Attempt.ManifestBinding(
        validatedRoundIdentifier: Array(repeating: 0xB1, count: 32),
        validatedManifestDigest: Array(repeating: 0xB2, count: 32)
    )
    static let transcriptRootA = try! Attempt.TranscriptRoot(
        validating: Array(repeating: 0xC3, count: 32)
    )
    static let transcriptRootB = try! Attempt.TranscriptRoot(
        validating: Array(repeating: 0xD4, count: 32)
    )

    static func makeControlIdentity(
        position: Int,
        identityOffset: UInt8 = 0
    ) -> Attempt.ControlIdentity {
        MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: identityOffset &+ UInt8(position + 1)
        )
    }

    static func makeRoster(
        candidateCount: Int,
        identityOffset: UInt8 = 0
    ) throws -> Attempt.Roster {
        try makeElection(
            candidateCount: candidateCount,
            identityOffset: identityOffset
        ).result.roster
    }

    static func makeElection(
        candidateCount: Int,
        identityOffset: UInt8 = 0
    ) throws -> MosaicRoleElectionFixtures.Election {
        try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: (0 ..< candidateCount).map { position in
                makeControlIdentity(
                    position: position,
                    identityOffset: identityOffset
                )
            },
            profile: configuration.profile
        )
    }

    static func makeValidatedAttempt(
        election: MosaicRoleElectionFixtures.Election
    ) -> Attempt {
        var attempt = Attempt(configuration: configuration)
        _ = attempt.apply(
            input: .discoveryCompleted(
                candidateCount: election.controlRoster.candidateCount
            )
        )
        _ = attempt.apply(input: .candidateSetAgreementValidated)
        _ = attempt.apply(
            input: .controlRosterValidated(election.controlRoster)
        )
        _ = attempt.apply(
            input: .roleCommitmentsReceived(election.commitments)
        )
        _ = attempt.apply(
            input: .roleElectionValidated(election.validation)
        )
        return attempt
    }

    static func makeSimulator(
        candidateCount: Int = 7,
        attemptByte: UInt8 = 0x11,
        generationByte: UInt8 = 0x21,
        identityOffset: UInt8 = 0,
        materialOffset: UInt8 = 0x30
    ) throws -> Simulator {
        let election = try makeElection(
            candidateCount: candidateCount,
            identityOffset: identityOffset
        )
        return try Simulator(
            validatedAttempt: makeValidatedAttempt(election: election),
            attemptIdentifier: .init(validatedBytes: [attemptByte]),
            generationIdentifier: .init(opaqueBytes: [generationByte]),
            materialIdentifiers: (0 ..< candidateCount).map { position in
                .init(opaqueBytes: [materialOffset &+ UInt8(position)])
            }
        )
    }

    static func makeManifestSignatureValidations(
        roster: Attempt.Roster,
        manifest: Attempt.ManifestBinding
    ) -> [Attempt.ManifestSignatureValidation] {
        let cachedValidations: [Attempt.ManifestSignatureValidation]?
        if manifest == manifestA {
            switch roster.candidateCount {
            case 7:
                cachedValidations = manifestASevenCandidateValidations
            case 8:
                cachedValidations = manifestAEightCandidateValidations
            case 9:
                cachedValidations = manifestANineCandidateValidations
            default:
                cachedValidations = nil
            }
        } else if manifest == manifestB, roster.candidateCount == 7 {
            cachedValidations = manifestBRetryValidations
        } else {
            cachedValidations = nil
        }
        if let cachedValidations,
           roster.controlIdentities == cachedValidations.map(\.signer) {
            return cachedValidations
        }
        return MosaicManifestSignatureFixtures.manifestSignatureValidations(
            for: roster,
            binding: manifest
        )
    }

    private static let manifestASevenCandidateValidations =
        cachedManifestValidations(
            candidateCount: 7,
            binding: manifestA
        )

    private static let manifestAEightCandidateValidations =
        cachedManifestValidations(
            candidateCount: 8,
            binding: manifestA
        )

    private static let manifestANineCandidateValidations =
        cachedManifestValidations(
            candidateCount: 9,
            binding: manifestA
        )

    private static let manifestBRetryValidations = cachedManifestValidations(
        candidateCount: 7,
        identityOffset: 0x40,
        binding: manifestB
    )

    private static func cachedManifestValidations(
        candidateCount: Int,
        identityOffset: UInt8 = 0,
        binding: Attempt.ManifestBinding
    ) -> [Attempt.ManifestSignatureValidation] {
        let roster = try! makeRoster(
            candidateCount: candidateCount,
            identityOffset: identityOffset
        )
        return MosaicManifestSignatureFixtures.manifestSignatureValidations(
            for: roster,
            binding: binding
        )
    }

    static func makeTranscriptAcknowledgements(
        roster: Attempt.Roster,
        manifest: Attempt.ManifestBinding = manifestA,
        transcriptRoot: Attempt.TranscriptRoot
    ) -> [Attempt.TranscriptAcknowledgementValidation] {
        MosaicManifestSignatureFixtures.transcriptAcknowledgementValidations(
            for: roster.contributors,
            binding: manifest,
            transcriptRoot: transcriptRoot
        )
    }

    static func complete(
        simulator: inout Simulator,
        manifest: Attempt.ManifestBinding = manifestA
    ) throws {
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: simulator.roster,
            manifest: manifest
        )
        _ = simulator.broadcast(
            attemptInput: .manifestSignaturesValidated(
                makeManifestSignatureValidations(
                    roster: simulator.roster,
                    manifest: manifest
                )
            )
        )
        _ = simulator.broadcast(
            attemptInput: .walletReservationsPrepared(
                contributors: simulator.roster.contributors
            )
        )
        _ = simulator.broadcast(
            attemptInput: .groupedCommitmentSetReceived(
                preparation.commitmentSet
            )
        )
        _ = simulator.broadcast(
            attemptInput: .anonymousComponentSetReceived(
                preparation.componentSet
            )
        )
        _ = try simulator.validateTranscriptInclusion(preparation.transcript)
        _ = simulator.broadcast(
            attemptInput: .transcriptAgreementValidated(
                makeTranscriptAcknowledgements(
                    roster: simulator.roster,
                    manifest: manifest,
                    transcriptRoot: preparation.transcript.transcriptRoot
                )
            )
        )
        _ = simulator.broadcast(
            attemptInput: .signedTransactionValidated(
                contributorSigners: simulator.roster.contributors
            )
        )
    }

    static func findLocalAttempt(
        for controlIdentity: Attempt.ControlIdentity,
        in simulator: Simulator
    ) -> LocalAttempt {
        guard let localAttempt = simulator.localAttempts.first(where: {
            $0.localControlIdentity == controlIdentity
        }) else {
            preconditionFailure("The local attempt must exist for every validated roster member")
        }
        return localAttempt
    }

    static func countReservationEligibility(
        in effects: [LocalAttempt.Effect]
    ) -> Int {
        effects.reduce(into: 0) { count, effect in
            if case .walletReservationEligible = effect {
                count += 1
            }
        }
    }

    static func countSigningEligibility(
        in effects: [LocalAttempt.Effect]
    ) -> Int {
        effects.reduce(into: 0) { count, effect in
            if case .bchSigningEligible = effect {
                count += 1
            }
        }
    }

    static func countPreSignRequirements(
        in effects: [LocalAttempt.Effect]
    ) -> Int {
        effects.reduce(into: 0) { count, effect in
            if case .preSignAcknowledgementRequired = effect {
                count += 1
            }
        }
    }

    static func countTranscriptInclusionRequirements(
        in effects: [LocalAttempt.Effect]
    ) -> Int {
        effects.reduce(into: 0) { count, effect in
            if case .transcriptInclusionValidationRequired = effect {
                count += 1
            }
        }
    }

    static func countReleaseRequirements(
        in effects: [LocalAttempt.Effect]
    ) -> Int {
        effects.reduce(into: 0) { count, effect in
            if case .walletReservationReleaseRequired = effect {
                count += 1
            }
        }
    }

    static func countCommitRequirements(
        in effects: [LocalAttempt.Effect]
    ) -> Int {
        effects.reduce(into: 0) { count, effect in
            if case .walletReservationCommitRequired = effect {
                count += 1
            }
        }
    }

    static func countContributorAuthorityEffects(
        in effects: [LocalAttempt.Effect]
    ) -> Int {
        countReservationEligibility(in: effects)
            + countTranscriptInclusionRequirements(in: effects)
            + countPreSignRequirements(in: effects)
            + countSigningEligibility(in: effects)
            + countReleaseRequirements(in: effects)
            + countCommitRequirements(in: effects)
    }
}
