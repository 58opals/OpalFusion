// MosaicSemanticValidator+Fixtures.swift

@testable import OpalFusion

extension MosaicSemanticValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Simulator = MosaicSemanticSimulator

    static let manifestA = Attempt.ManifestIdentifier(validatedBytes: [0xA1])
    static let manifestB = Attempt.ManifestIdentifier(validatedBytes: [0xB2])
    static let transcriptRootA = Attempt.TranscriptRoot(validatedBytes: [0xC3])
    static let transcriptRootB = Attempt.TranscriptRoot(validatedBytes: [0xD4])

    static func makeControlIdentity(
        position: Int,
        identityOffset: UInt8 = 0
    ) -> Attempt.ControlIdentity {
        .init(validatedBytes: [identityOffset &+ UInt8(position + 1)])
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

    static func makeManifestAcknowledgements(
        roster: Attempt.Roster,
        manifest: Attempt.ManifestIdentifier
    ) -> [Attempt.ManifestAcknowledgement] {
        roster.controlIdentities.map {
            .init(signer: $0, manifest: manifest)
        }
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
        manifest: Attempt.ManifestIdentifier = manifestA,
        transcriptRoot: Attempt.TranscriptRoot = transcriptRootA
    ) {
        _ = simulator.broadcast(
            validatedFact: .manifestAgreementValidated(
                makeManifestAcknowledgements(
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
