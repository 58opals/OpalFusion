// MosaicSemanticValidator+Fixtures.swift

@testable import OpalFusion

extension MosaicSemanticValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Simulator = MosaicSemanticSimulator

    static let manifestA = try! Attempt.ManifestBinding(
        validatedRoundIdentifier: Array(repeating: 0xA1, count: 32),
        validatedManifestDigest: Array(repeating: 0xA2, count: 32)
    )
    static let manifestB = try! Attempt.ManifestBinding(
        validatedRoundIdentifier: Array(repeating: 0xB1, count: 32),
        validatedManifestDigest: Array(repeating: 0xB2, count: 32)
    )
    static let transcriptRootA = Attempt.TranscriptRoot(validatedBytes: [0xC3])
    static let transcriptRootB = Attempt.TranscriptRoot(validatedBytes: [0xD4])

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
        try .init(
            members: (0 ..< candidateCount).map { position in
                .init(
                    controlIdentity: makeControlIdentity(
                        position: position,
                        identityOffset: identityOffset
                    ),
                    role: position == 0 ? .conductor : .contributor
                )
            }
        )
    }

    static func makeValidatedAttempt(
        roster: Attempt.Roster
    ) -> Attempt {
        var attempt = Attempt()
        _ = attempt.apply(
            input: .discoveryCompleted(candidateCount: roster.candidateCount)
        )
        _ = attempt.apply(input: .candidateSetAgreementValidated)
        _ = attempt.apply(
            input: .controlRosterValidated(roster.controlIdentities)
        )
        _ = attempt.apply(input: .rolesSelected(roster))
        return attempt
    }

    static func makeSimulator(
        candidateCount: Int = 7,
        attemptByte: UInt8 = 0x11,
        generationByte: UInt8 = 0x21,
        identityOffset: UInt8 = 0,
        materialOffset: UInt8 = 0x30
    ) throws -> Simulator {
        let roster = try makeRoster(
            candidateCount: candidateCount,
            identityOffset: identityOffset
        )
        return try Simulator(
            validatedAttempt: makeValidatedAttempt(roster: roster),
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
        transcriptRoot: Attempt.TranscriptRoot
    ) -> [Attempt.TranscriptAcknowledgement] {
        roster.contributors.map {
            .init(contributor: $0, transcriptRoot: transcriptRoot)
        }
    }

    static func complete(
        simulator: inout Simulator,
        manifest: Attempt.ManifestBinding = manifestA,
        transcriptRoot: Attempt.TranscriptRoot = transcriptRootA
    ) {
        _ = simulator.broadcast(
            validatedFact: .manifestSignaturesValidated(
                makeManifestSignatureValidations(
                    roster: simulator.roster,
                    manifest: manifest
                )
            )
        )
        _ = simulator.broadcast(
            validatedFact: .walletReservationsPrepared(
                contributors: simulator.roster.contributors
            )
        )
        _ = simulator.broadcast(
            validatedFact: .groupedCommitmentsValidated(
                contributors: simulator.roster.contributors
            )
        )
        _ = simulator.broadcast(
            validatedFact: .anonymousComponentsValidated(
                contributors: simulator.roster.contributors
            )
        )
        _ = simulator.broadcast(
            validatedFact: .transcriptAgreementValidated(
                makeTranscriptAcknowledgements(
                    roster: simulator.roster,
                    transcriptRoot: transcriptRoot
                )
            )
        )
        _ = simulator.broadcast(
            validatedFact: .signedTransactionValidated(
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
            + countSigningEligibility(in: effects)
            + countReleaseRequirements(in: effects)
            + countCommitRequirements(in: effects)
    }
}
