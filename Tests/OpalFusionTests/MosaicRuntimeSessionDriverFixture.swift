// MosaicRuntimeSessionDriverFixture.swift

@testable import OpalFusion

enum MosaicRuntimeSessionDriverFixture {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Driver = OpalFusion.Mosaic.RuntimeSessionDriver
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias RuntimeSession = OpalFusion.Mosaic.RuntimeSession

    enum Target: Equatable {
        case manifestAgreement
        case walletReservation
        case bchSigning
    }

    static func makeSession(
        target: Target = .manifestAgreement,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> RuntimeSession {
        try makeFixture(target: target, profile: profile).session
    }

    static func makeFixture(
        target: Target = .manifestAgreement,
        profile: OpalFusion.Mosaic.Profile = .opalV0
    ) throws -> MosaicRuntimeSessionFixture {
        let configuration = OpalFusion.Mosaic.Configuration(profile: profile)
        let controlIdentities = (1 ... 7).map {
            MosaicManifestSignatureFixtures.controlIdentity(
                scalarByte: UInt8($0)
            )
        }
        let election = try MosaicRoleElectionFixtures.makeElection(
            controlIdentities: controlIdentities,
            profile: profile
        )
        var attempt = Attempt(configuration: configuration)
        _ = attempt.apply(input: .discoveryCompleted(candidateCount: 7))
        _ = attempt.apply(input: .candidateSetAgreementValidated)
        _ = attempt.apply(input: .controlRosterValidated(election.controlRoster))
        _ = attempt.apply(input: .roleCommitmentsReceived(election.commitments))
        _ = attempt.apply(input: .roleElectionValidated(election.validation))

        let attemptIdentifier = LocalAttempt.AttemptIdentifier(
            validatedBytes: [0xA1]
        )
        let generationIdentifier = LocalAttempt.GenerationIdentifier(
            opaqueBytes: [0xB2]
        )
        let materialIdentifier = LocalAttempt.MaterialIdentifier(
            opaqueBytes: [0xC3]
        )
        let localAttempt = try LocalAttempt(
            validatedAttempt: attempt,
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            materialIdentifier: materialIdentifier,
            localControlIdentity: election.result.roster.contributors[0]
        )
        var runtimeSession = try RuntimeSession(localAttempt: localAttempt)

        let manifest = try Attempt.ManifestBinding(
            validatedRoundIdentifier: Array(repeating: 0xD4, count: 32),
            validatedManifestDigest: Array(repeating: 0xD5, count: 32)
        )
        let transactionPreparation = try
            MosaicUnsignedTransactionTranscriptFixtures.prepare(
                roster: election.result.roster,
                manifest: manifest
            )
        let fixture = MosaicRuntimeSessionFixture(
            session: runtimeSession,
            roster: election.result.roster,
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            materialIdentifier: materialIdentifier,
            manifest: manifest,
            transactionPreparation: transactionPreparation
        )

        guard target != .manifestAgreement else {
            return fixture
        }

        _ = runtimeSession.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 0,
                    phase: .manifestAgreement,
                    identifierByte: 0xE6,
                    fact: .manifestSignatureSet(
                        binding: manifest,
                        signatures: MosaicManifestSignatureFixtures
                            .manifestSignatures(
                                for: election.result.roster,
                                binding: manifest
                            )
                    )
                )
            )
        )

        guard target != .walletReservation else {
            return replacingSession(in: fixture, with: runtimeSession)
        }

        _ = runtimeSession.apply(
            input: .hostResult(
                .walletReservationsPrepared(
                    attemptIdentifier: attemptIdentifier,
                    generationIdentifier: generationIdentifier,
                    contributors: election.result.roster.contributors
                )
            )
        )
        _ = runtimeSession.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 1,
                    phase: .groupedCommitment,
                    identifierByte: 0xE7,
                    fact: .groupedCommitmentSet(
                        transactionPreparation.commitmentSet
                    )
                )
            )
        )
        _ = runtimeSession.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 2,
                    phase: .anonymousComponentSubmission,
                    identifierByte: 0xE8,
                    fact: .anonymousComponentSet(
                        transactionPreparation.componentSet
                    )
                )
            )
        )
        _ = runtimeSession.apply(
            input: .local(
                .transcriptInclusionValidated(
                    try MosaicUnsignedTransactionTranscriptFixtures
                        .makeTranscriptInclusionValidation(
                            attemptIdentifier: attemptIdentifier,
                            generationIdentifier: generationIdentifier,
                            contributor: election.result.roster.contributors[0],
                            materialIdentifier: materialIdentifier,
                            transcript: transactionPreparation.transcript
                        )
                )
            )
        )
        _ = runtimeSession.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 3,
                    phase: .transcriptAgreement,
                    identifierByte: 0xE9,
                    fact: .transcriptAcknowledgementSet(
                        MosaicManifestSignatureFixtures
                            .transcriptAcknowledgements(
                                for: election.result.roster.contributors,
                                binding: manifest,
                                transcriptRoot:
                                    transactionPreparation.transcript.transcriptRoot
                            )
                    )
                )
            )
        )

        precondition(
            runtimeSession.state.phase == .bchSigning,
            "The signing fixture must cross every pre-sign gate"
        )
        return replacingSession(in: fixture, with: runtimeSession)
    }

    private static func makeMessage(
        fixture: MosaicRuntimeSessionFixture,
        sequence: UInt64,
        phase: Attempt.Phase,
        identifierByte: UInt8,
        fact: RuntimeSession.AuthenticatedFact
    ) throws -> RuntimeSession.AuthenticatedMessage {
        .init(
            attemptIdentifier: fixture.attemptIdentifier,
            generationIdentifier: fixture.generationIdentifier,
            sender: fixture.roster.conductor,
            sequence: sequence,
            phase: phase,
            messageIdentifier: try .init(
                bytes: Array(repeating: identifierByte, count: 32)
            ),
            authenticatedFact: fact
        )
    }

    private static func replacingSession(
        in fixture: MosaicRuntimeSessionFixture,
        with session: RuntimeSession
    ) -> MosaicRuntimeSessionFixture {
        .init(
            session: session,
            roster: fixture.roster,
            attemptIdentifier: fixture.attemptIdentifier,
            generationIdentifier: fixture.generationIdentifier,
            materialIdentifier: fixture.materialIdentifier,
            manifest: fixture.manifest,
            transactionPreparation: fixture.transactionPreparation
        )
    }
}
