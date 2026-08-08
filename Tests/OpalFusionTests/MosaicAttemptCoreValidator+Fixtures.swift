// MosaicAttemptCoreValidator+Fixtures.swift

@testable import OpalFusion

extension MosaicAttemptCoreValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    struct Scenario {
        var attempt: Attempt
        let roster: Attempt.Roster
    }

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

    static func controlIdentity(_ value: UInt8) -> Attempt.ControlIdentity {
        MosaicManifestSignatureFixtures.controlIdentity(scalarByte: value)
    }

    static func makeMembers(
        candidateCount: Int,
        conductorIndexes: Set<Int> = [0]
    ) -> [Attempt.RosterMember] {
        (0 ..< candidateCount).map { index in
            .init(
                controlIdentity: controlIdentity(UInt8(index + 1)),
                role: conductorIndexes.contains(index) ? .conductor : .contributor
            )
        }
    }

    static func makeRoster(candidateCount: Int = 7) throws -> Attempt.Roster {
        try .init(members: makeMembers(candidateCount: candidateCount))
    }

    static func manifestSignatureValidations(
        for roster: Attempt.Roster,
        manifest: Attempt.ManifestBinding = manifestA
    ) -> [Attempt.ManifestSignatureValidation] {
        if manifest == manifestA,
           roster.controlIdentities == manifestASevenCandidateValidations.map(\.signer) {
            return manifestASevenCandidateValidations
        }
        return MosaicManifestSignatureFixtures.manifestSignatureValidations(
            for: roster,
            binding: manifest
        )
    }

    private static let manifestASevenCandidateValidations =
        MosaicManifestSignatureFixtures.manifestSignatureValidations(
            for: try! .init(members: makeMembers(candidateCount: 7)),
            binding: manifestA
        )

    static func transcriptAcknowledgements(
        for roster: Attempt.Roster,
        transcriptRoot: Attempt.TranscriptRoot = transcriptRootA
    ) -> [Attempt.TranscriptAcknowledgement] {
        roster.contributors.map {
            .init(contributor: $0, transcriptRoot: transcriptRoot)
        }
    }

    static func makeScenario(
        at targetPhase: Attempt.Phase,
        candidateCount: Int = 7
    ) throws -> Scenario {
        var attempt = Attempt()
        let roster = try makeRoster(candidateCount: candidateCount)

        if targetPhase.rawValue >= Attempt.Phase.candidateSetAgreement.rawValue {
            _ = attempt.apply(input: .discoveryCompleted(candidateCount: candidateCount))
        }
        if targetPhase.rawValue >= Attempt.Phase.controlRosterAgreement.rawValue {
            _ = attempt.apply(input: .candidateSetAgreementValidated)
        }
        if targetPhase.rawValue >= Attempt.Phase.roleSelection.rawValue {
            _ = attempt.apply(
                input: .controlRosterValidated(roster.controlIdentities)
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.manifestAgreement.rawValue {
            _ = attempt.apply(input: .rolesSelected(roster))
        }
        if targetPhase.rawValue >= Attempt.Phase.walletReservation.rawValue {
            _ = attempt.apply(
                input: .manifestSignaturesValidated(
                    manifestSignatureValidations(for: roster)
                )
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.groupedCommitment.rawValue {
            _ = attempt.apply(
                input: .walletReservationsPrepared(
                    contributors: roster.contributors
                )
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.anonymousComponentSubmission.rawValue {
            _ = attempt.apply(
                input: .groupedCommitmentsValidated(
                    contributors: roster.contributors
                )
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.transcriptAgreement.rawValue {
            _ = attempt.apply(
                input: .anonymousComponentsValidated(
                    contributors: roster.contributors
                )
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.bchSigning.rawValue {
            _ = attempt.apply(
                input: .transcriptAgreementValidated(
                    transcriptAcknowledgements(for: roster)
                )
            )
        }

        return Scenario(attempt: attempt, roster: roster)
    }

    static func terminationEffects(
        outcome: Attempt.Outcome,
        reservationRoster: Attempt.Roster?
    ) -> [Attempt.Effect] {
        var effects: [Attempt.Effect] = []
        if outcome != .completed, let reservationRoster {
            effects.append(
                .walletReservationReleaseRequired(
                    contributors: reservationRoster.contributors
                )
            )
        }
        effects.append(.attemptTerminated(outcome))
        return effects
    }

    static func expectedReservationRoster(
        during phase: Attempt.Phase,
        roster: Attempt.Roster
    ) -> Attempt.Roster? {
        switch phase {
        case .discovery, .candidateSetAgreement, .controlRosterAgreement,
             .roleSelection, .manifestAgreement:
            nil
        case .walletReservation, .groupedCommitment,
             .anonymousComponentSubmission, .transcriptAgreement, .bchSigning:
            roster
        }
    }

    static func contributorInput(
        for phase: Attempt.Phase,
        contributors: [Attempt.ControlIdentity]
    ) -> Attempt.Input {
        switch phase {
        case .walletReservation:
            .walletReservationsPrepared(contributors: contributors)
        case .groupedCommitment:
            .groupedCommitmentsValidated(contributors: contributors)
        case .anonymousComponentSubmission:
            .anonymousComponentsValidated(contributors: contributors)
        case .bchSigning:
            .signedTransactionValidated(contributorSigners: contributors)
        case .discovery, .candidateSetAgreement, .controlRosterAgreement,
             .roleSelection, .manifestAgreement, .transcriptAgreement:
            preconditionFailure("Phase does not consume a contributor-set input")
        }
    }
}
