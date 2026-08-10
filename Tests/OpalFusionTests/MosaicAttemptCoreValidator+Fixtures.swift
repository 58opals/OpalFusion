// MosaicAttemptCoreValidator+Fixtures.swift

@testable import OpalFusion

extension MosaicAttemptCoreValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt

    struct Scenario {
        var attempt: Attempt
        let election: MosaicRoleElectionFixtures.Election
        let transactionPreparation:
            MosaicUnsignedTransactionTranscriptFixtures.Prepared

        var roster: Attempt.Roster {
            election.result.roster
        }
    }

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

    static func makeElection(
        candidateCount: Int = 7,
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        roleSeed: [UInt8] = Array(repeating: 0, count: 32)
    ) throws -> MosaicRoleElectionFixtures.Election {
        try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: makeMembers(candidateCount: candidateCount).map(
                \.controlIdentity
            ),
            profile: profile,
            roleSeed: roleSeed
        )
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
            for: try! makeElection(candidateCount: 7).result.roster,
            binding: manifestA
        )

    static func transcriptAcknowledgements(
        for roster: Attempt.Roster,
        manifest: Attempt.ManifestBinding = manifestA,
        transcriptRoot: Attempt.TranscriptRoot = transcriptRootA,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) -> [Attempt.TranscriptAcknowledgementValidation] {
        MosaicManifestSignatureFixtures.transcriptAcknowledgementValidations(
            for: roster.contributors,
            binding: manifest,
            transcriptRoot: transcriptRoot,
            profile: profile
        )
    }

    static func transcriptAcknowledgement(
        contributor: Attempt.ControlIdentity,
        manifest: Attempt.ManifestBinding = manifestA,
        transcriptRoot: Attempt.TranscriptRoot = transcriptRootA,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) -> Attempt.TranscriptAcknowledgementValidation {
        MosaicManifestSignatureFixtures.transcriptAcknowledgementValidation(
            contributor: contributor,
            binding: manifest,
            transcriptRoot: transcriptRoot,
            profile: profile
        )
    }

    static func makeScenario(
        at targetPhase: Attempt.Phase,
        candidateCount: Int = 7,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> Scenario {
        var attempt = Attempt(configuration: .init(profile: profile))
        let election = try makeElection(
            candidateCount: candidateCount,
            profile: profile
        )
        let roster = election.result.roster
        let transactionPreparation = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: roster,
                manifest: manifestA,
                profile: profile
            )

        if targetPhase.rawValue >= Attempt.Phase.candidateSetAgreement.rawValue {
            _ = attempt.apply(input: .discoveryCompleted(candidateCount: candidateCount))
        }
        if targetPhase.rawValue >= Attempt.Phase.controlRosterAgreement.rawValue {
            _ = attempt.apply(input: .candidateSetAgreementValidated)
        }
        if targetPhase.rawValue >= Attempt.Phase.roleSelection.rawValue {
            _ = attempt.apply(
                input: .controlRosterValidated(election.controlRoster)
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.manifestAgreement.rawValue {
            _ = attempt.apply(
                input: .roleCommitmentsReceived(election.commitments)
            )
            _ = attempt.apply(
                input: .roleElectionValidated(election.validation)
            )
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
                input: .groupedCommitmentSetReceived(
                    transactionPreparation.commitmentSet
                )
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.transcriptAgreement.rawValue {
            _ = attempt.apply(
                input: .anonymousComponentSetReceived(
                    transactionPreparation.componentSet
                )
            )
        }
        if targetPhase.rawValue >= Attempt.Phase.bchSigning.rawValue {
            _ = attempt.apply(
                input: .transcriptAgreementValidated(
                    transcriptAcknowledgements(
                        for: roster,
                        transcriptRoot: transactionPreparation.transcript.transcriptRoot,
                        profile: profile
                    )
                )
            )
        }

        return Scenario(
            attempt: attempt,
            election: election,
            transactionPreparation: transactionPreparation
        )
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
        contributors: [Attempt.ControlIdentity],
        roster: Attempt.Roster
    ) throws -> Attempt.Input {
        switch phase {
        case .walletReservation:
            return .walletReservationsPrepared(contributors: contributors)
        case .bchSigning:
            return .signedTransactionValidated(contributorSigners: contributors)
        case .discovery, .candidateSetAgreement, .controlRosterAgreement,
             .roleSelection, .manifestAgreement, .groupedCommitment,
             .anonymousComponentSubmission, .transcriptAgreement:
            preconditionFailure("Phase does not consume a contributor-set input")
        }
    }
}
