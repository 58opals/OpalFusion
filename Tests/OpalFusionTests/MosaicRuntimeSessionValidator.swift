// MosaicRuntimeSessionValidator.swift

import Foundation
import Testing
@testable import OpalFusion

@Suite("Mosaic authenticated runtime and replay validation")
struct MosaicRuntimeSessionValidator {
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias RuntimeSession = OpalFusion.Mosaic.RuntimeSession

    @Test("Accept a signed fact once and ignore its exact duplicate")
    func acceptOnceAndIgnoreExactDuplicate() throws {
        var fixture = try makeFixture()
        let message = try makeManifestMessage(fixture: fixture, sequence: 0)

        let firstEffects = fixture.session.apply(input: .authenticated(message))
        let duplicateEffects = fixture.session.apply(input: .authenticated(message))

        #expect(firstEffects.contains { effect in
            if case .localAttempt(.walletReservationEligible) = effect {
                return true
            }
            return false
        })
        #expect(duplicateEffects == [.exactDuplicateIgnored])
        #expect(
            fixture.session.state
                == .walletReservation(
                    roster: fixture.roster,
                    manifest: fixture.manifest
                )
        )
    }

    @Test("Abort invalid embedded manifest signatures without reservation")
    func abortInvalidManifestSignatureAndKeepReplayTerminal() throws {
        var fixture = try makeFixture()
        let valid = try makeManifestMessage(fixture: fixture, sequence: 0)
        guard case let .manifestSignatureSet(binding, signatures) =
            valid.authenticatedFact
        else {
            Issue.record("Expected a manifest signature set fixture")
            return
        }
        var invalidSignatures = signatures
        invalidSignatures[0] = .init(
            signer: invalidSignatures[0].signer,
            rawRepresentation: Array(repeating: 0xFF, count: 64)
        )
        let invalid = RuntimeSession.AuthenticatedMessage(
            attemptIdentifier: valid.attemptIdentifier,
            generationIdentifier: valid.generationIdentifier,
            sender: valid.sender,
            sequence: valid.sequence,
            phase: valid.phase,
            messageIdentifier: valid.messageIdentifier,
            authenticatedFact: .manifestSignatureSet(
                binding: binding,
                signatures: invalidSignatures
            )
        )

        let firstEffects = fixture.session.apply(input: .authenticated(invalid))

        #expect(
            firstEffects.first
                == .authenticatedInputRejected(
                    .invalidManifestSignature(.invalidSignature)
                )
        )
        #expect(firstEffects.allSatisfy { effect in
            if case .localAttempt(.walletReservationEligible) = effect {
                return false
            }
            return true
        })
        #expect(
            fixture.session.state == .terminal(
                .failed(
                    .aborted(
                        during: .manifestAgreement,
                        reason: .invalidAuthenticatedMessage
                    )
                )
            )
        )
        #expect(
            fixture.session.apply(input: .authenticated(invalid))
                == [.exactDuplicateIgnored]
        )

        let corrected = try makeManifestMessage(
            fixture: fixture,
            sequence: 0,
            identifierByte: 0x92
        )
        #expect(
            fixture.session.apply(input: .authenticated(corrected))
                == [
                    .localAttempt(
                        .inputRejected(.attemptFailure(.inputAfterTermination))
                    )
                ]
        )
    }

    @Test("Reject oversized manifest signature sets before cryptographic work")
    func rejectOversizedManifestSignatureSetBeforeVerification() throws {
        var fixture = try makeFixture()
        let valid = try makeManifestMessage(fixture: fixture, sequence: 0)
        guard case let .manifestSignatureSet(binding, _) =
            valid.authenticatedFact
        else {
            Issue.record("Expected a manifest signature set fixture")
            return
        }
        let hostileSignature = Attempt.ManifestSignature(
            signer: .init(validatedBytes: []),
            rawRepresentation: []
        )
        let actualCount = fixture.roster.candidateCount + 1
        let oversized = RuntimeSession.AuthenticatedMessage(
            attemptIdentifier: valid.attemptIdentifier,
            generationIdentifier: valid.generationIdentifier,
            sender: valid.sender,
            sequence: valid.sequence,
            phase: valid.phase,
            messageIdentifier: valid.messageIdentifier,
            authenticatedFact: .manifestSignatureSet(
                binding: binding,
                signatures: Array(
                    repeating: hostileSignature,
                    count: actualCount
                )
            )
        )

        let effects = fixture.session.apply(input: .authenticated(oversized))

        #expect(
            effects.first
                == .authenticatedInputRejected(
                    .invalidManifestSignatureCount(
                        expected: fixture.roster.candidateCount,
                        actual: actualCount
                    )
                )
        )
        #expect(effects.allSatisfy { effect in
            if case .localAttempt(.walletReservationEligible) = effect {
                return false
            }
            return true
        })
        if case .terminal(.failed) = fixture.session.state {
            // Expected.
        } else {
            Issue.record("Expected oversized signature input to terminate")
        }
    }

    @Test("Abort on one sender reusing a sequence for a different message")
    func abortOnSequenceConflict() throws {
        var fixture = try makeFixture()
        let original = try makeManifestMessage(fixture: fixture, sequence: 4)
        var conflicting = try makeManifestMessage(
            fixture: fixture,
            sequence: 4,
            identifierByte: 0x92
        )
        conflicting = .init(
            attemptIdentifier: conflicting.attemptIdentifier,
            generationIdentifier: conflicting.generationIdentifier,
            sender: conflicting.sender,
            sequence: conflicting.sequence,
            phase: conflicting.phase,
            messageIdentifier: conflicting.messageIdentifier,
            authenticatedFact: .abort(.equivocation)
        )

        _ = fixture.session.apply(input: .authenticated(original))
        let effects = fixture.session.apply(input: .authenticated(conflicting))

        #expect(effects.first == .authenticatedInputRejected(.sequenceConflict))
        #expect(
            fixture.session.state == .terminal(
                .failed(
                    .aborted(
                        during: .walletReservation,
                        reason: .equivocation
                    )
                )
            )
        )
        #expect(effects.contains { effect in
            if case .localAttempt(.walletReservationReleaseRequired) = effect {
                return true
            }
            return false
        })
    }

    @Test("Abort a roster sender whose envelope claims the wrong phase")
    func abortOnEnvelopePhaseMismatch() throws {
        var fixture = try makeFixture()
        let message = try makeManifestMessage(
            fixture: fixture,
            sequence: 0,
            phase: .walletReservation
        )

        let effects = fixture.session.apply(input: .authenticated(message))

        #expect(effects.first == .authenticatedInputRejected(.phaseMismatch))
        #expect(
            fixture.session.state == .terminal(
                .failed(
                    .aborted(
                        during: .manifestAgreement,
                        reason: .invalidAuthenticatedMessage
                    )
                )
            )
        )
    }

    @Test("Reject stale sequence without rolling back or terminating")
    func rejectStaleSequenceWithoutRollback() throws {
        var fixture = try makeFixture()
        _ = fixture.session.apply(
            input: .authenticated(
                try makeManifestMessage(fixture: fixture, sequence: 8)
            )
        )
        let stale = try RuntimeSession.AuthenticatedMessage(
            attemptIdentifier: fixture.attemptIdentifier,
            generationIdentifier: fixture.generationIdentifier,
            sender: fixture.roster.conductor,
            sequence: 7,
            phase: .walletReservation,
            messageIdentifier: .init(bytes: Array(repeating: 0x44, count: 32)),
            authenticatedFact: .abort(.timeout)
        )

        let effects = fixture.session.apply(input: .authenticated(stale))

        #expect(
            effects == [
                .authenticatedInputRejected(
                    .staleSequence(greatestAccepted: 8, received: 7)
                )
            ]
        )
        #expect(
            fixture.session.state
                == .walletReservation(
                    roster: fixture.roster,
                    manifest: fixture.manifest
                )
        )
    }

    @Test("Reject wrong attempt generation and sender before replay mutation")
    func rejectBindingsBeforeReplayMutation() throws {
        var fixture = try makeFixture()
        let valid = try makeManifestMessage(fixture: fixture, sequence: 3)
        let wrongAttempt = RuntimeSession.AuthenticatedMessage(
            attemptIdentifier: .init(validatedBytes: [0xFE]),
            generationIdentifier: valid.generationIdentifier,
            sender: valid.sender,
            sequence: valid.sequence,
            phase: valid.phase,
            messageIdentifier: valid.messageIdentifier,
            authenticatedFact: valid.authenticatedFact
        )
        let wrongGeneration = RuntimeSession.AuthenticatedMessage(
            attemptIdentifier: valid.attemptIdentifier,
            generationIdentifier: .init(opaqueBytes: [0xFD]),
            sender: valid.sender,
            sequence: valid.sequence,
            phase: valid.phase,
            messageIdentifier: valid.messageIdentifier,
            authenticatedFact: valid.authenticatedFact
        )
        let outsider = RuntimeSession.AuthenticatedMessage(
            attemptIdentifier: valid.attemptIdentifier,
            generationIdentifier: valid.generationIdentifier,
            sender: .init(validatedBytes: [0xFC]),
            sequence: valid.sequence,
            phase: valid.phase,
            messageIdentifier: valid.messageIdentifier,
            authenticatedFact: valid.authenticatedFact
        )

        #expect(
            fixture.session.apply(input: .authenticated(wrongAttempt))
                == [.authenticatedInputRejected(.attemptIdentifierMismatch)]
        )
        #expect(
            fixture.session.apply(input: .authenticated(wrongGeneration))
                == [.authenticatedInputRejected(.generationIdentifierMismatch)]
        )
        #expect(
            fixture.session.apply(input: .authenticated(outsider))
                == [.authenticatedInputRejected(.senderNotInRoster)]
        )
        #expect(
            fixture.session.apply(input: .authenticated(valid)).contains {
                if case .localAttempt(.walletReservationEligible) = $0 {
                    return true
                }
                return false
            }
        )
    }

    @Test("Reject unseen terminal input while ignoring a known aborting duplicate")
    func distinguishTerminalInputFromKnownDuplicate() throws {
        var fixture = try makeFixture()
        _ = fixture.session.apply(input: .local(.cancel))
        let unseen = try makeManifestMessage(fixture: fixture, sequence: 0)

        let unseenEffects = fixture.session.apply(input: .authenticated(unseen))

        #expect(
            unseenEffects == [
                .localAttempt(
                    .inputRejected(.attemptFailure(.inputAfterTermination))
                )
            ]
        )

        var abortFixture = try makeFixture()
        let aborting = try makeManifestMessage(
            fixture: abortFixture,
            sequence: 1,
            phase: .walletReservation
        )
        _ = abortFixture.session.apply(input: .authenticated(aborting))
        #expect(
            abortFixture.session.apply(input: .authenticated(aborting))
                == [.exactDuplicateIgnored]
        )
    }

    @Test("Ignore a previously accepted authenticated fact after completion")
    func ignoreAcceptedDuplicateAfterCompletion() throws {
        var fixture = try makeFixture()
        _ = fixture.session.apply(
            input: .authenticated(
                try makeManifestMessage(fixture: fixture, sequence: 0)
            )
        )
        _ = fixture.session.apply(
            input: .hostResult(
                .walletReservationsPrepared(
                    contributors: fixture.roster.contributors
                )
            )
        )
        _ = fixture.session.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 1,
                    phase: .groupedCommitment,
                    identifierByte: 0x92,
                    fact: .groupedCommitmentsValidated(
                        contributors: fixture.roster.contributors
                    )
                )
            )
        )
        _ = fixture.session.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 2,
                    phase: .anonymousComponentSubmission,
                    identifierByte: 0x93,
                    fact: .anonymousComponentsValidated(
                        contributors: fixture.roster.contributors
                    )
                )
            )
        )
        let transcript = try makeMessage(
            fixture: fixture,
            sequence: 3,
            phase: .transcriptAgreement,
            identifierByte: 0x94,
            fact: .transcriptAcknowledgementSet(
                MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                    for: fixture.roster.contributors,
                    binding: fixture.manifest,
                    transcriptRoot: try .init(
                        validating: Array(repeating: 0x55, count: 32)
                    )
                )
            )
        )
        _ = fixture.session.apply(input: .authenticated(transcript))
        _ = fixture.session.apply(
            input: .hostResult(
                .signedTransactionValidated(
                    contributorSigners: fixture.roster.contributors
                )
            )
        )

        #expect(
            fixture.session.apply(input: .authenticated(transcript))
                == [.exactDuplicateIgnored]
        )
        if case .terminal(.completed) = fixture.session.state {
            // Expected.
        } else {
            Issue.record("Expected a completed terminal attempt")
        }
    }

    @Test("Verify a complete signed transcript set before BCH signing eligibility")
    func verifyCompleteTranscriptAcknowledgementSet() throws {
        var fixture = try makeFixture()
        try advanceToTranscriptAgreement(fixture: &fixture)
        let root = try Attempt.TranscriptRoot(
            validating: Array(repeating: 0x55, count: 32)
        )
        let message = try makeMessage(
            fixture: fixture,
            sequence: 3,
            phase: .transcriptAgreement,
            identifierByte: 0x94,
            fact: .transcriptAcknowledgementSet(
                MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                    for: fixture.roster.contributors,
                    binding: fixture.manifest,
                    transcriptRoot: root
                )
            )
        )

        let effects = fixture.session.apply(input: .authenticated(message))

        #expect(effects.contains { effect in
            if case .localAttempt(.bchSigningEligible) = effect {
                return true
            }
            return false
        })
        #expect(
            fixture.session.state == .bchSigning(
                roster: fixture.roster,
                manifest: fixture.manifest,
                transcriptRoot: root
            )
        )
    }

    @Test(
        "Reject hostile transcript set counts before embedded signature parsing",
        arguments: [-1, 1]
    )
    func rejectTranscriptSetCountBeforeVerification(offset: Int) throws {
        var fixture = try makeFixture()
        try advanceToTranscriptAgreement(fixture: &fixture)
        let expectedCount = fixture.roster.contributors.count
        let actualCount = expectedCount + offset
        let hostile = Attempt.TranscriptAcknowledgement(
            contributor: .init(validatedBytes: []),
            roundIdentifier: [],
            transcriptRoot: [],
            rawRepresentation: []
        )
        let message = try makeMessage(
            fixture: fixture,
            sequence: 3,
            phase: .transcriptAgreement,
            identifierByte: 0x95,
            fact: .transcriptAcknowledgementSet(
                Array(repeating: hostile, count: actualCount)
            )
        )

        let effects = fixture.session.apply(input: .authenticated(message))

        #expect(
            effects.first == .authenticatedInputRejected(
                .invalidTranscriptAcknowledgementCount(
                    expected: expectedCount,
                    actual: actualCount
                )
            )
        )
        #expect(effects.allSatisfy { effect in
            if case .localAttempt(.bchSigningEligible) = effect {
                return false
            }
            return true
        })
        if case .terminal(.failed) = fixture.session.state {
            // Expected.
        } else {
            Issue.record("Expected hostile transcript count to terminate")
        }
    }

    @Test("Abort an invalid transcript signature without BCH signing eligibility")
    func abortInvalidTranscriptSignature() throws {
        var fixture = try makeFixture()
        try advanceToTranscriptAgreement(fixture: &fixture)
        let root = try Attempt.TranscriptRoot(
            validating: Array(repeating: 0x66, count: 32)
        )
        var acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: fixture.roster.contributors,
                binding: fixture.manifest,
                transcriptRoot: root
            )
        acknowledgements[0] = .init(
            contributor: acknowledgements[0].contributor,
            roundIdentifier: acknowledgements[0].roundIdentifier,
            transcriptRoot: acknowledgements[0].transcriptRoot,
            rawRepresentation: Array(repeating: 0xFF, count: 64)
        )
        let invalid = try makeMessage(
            fixture: fixture,
            sequence: 3,
            phase: .transcriptAgreement,
            identifierByte: 0x96,
            fact: .transcriptAcknowledgementSet(acknowledgements)
        )

        let effects = fixture.session.apply(input: .authenticated(invalid))

        #expect(
            effects.first == .authenticatedInputRejected(
                .invalidTranscriptAcknowledgement(.invalidSignature)
            )
        )
        #expect(effects.filter { effect in
            if case .localAttempt(.walletReservationReleaseRequired) = effect {
                return true
            }
            return false
        }.count == 1)
        #expect(effects.allSatisfy { effect in
            if case .localAttempt(.bchSigningEligible) = effect {
                return false
            }
            return true
        })
        #expect(
            fixture.session.apply(input: .authenticated(invalid))
                == [.exactDuplicateIgnored]
        )

        let corrected = try makeMessage(
            fixture: fixture,
            sequence: 3,
            phase: .transcriptAgreement,
            identifierByte: 0x97,
            fact: .transcriptAcknowledgementSet(
                MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                    for: fixture.roster.contributors,
                    binding: fixture.manifest,
                    transcriptRoot: root
                )
            )
        )
        #expect(
            fixture.session.apply(input: .authenticated(corrected))
                == [
                    .localAttempt(
                        .inputRejected(.attemptFailure(.inputAfterTermination))
                    )
                ]
        )
    }

    @Test("Reject a complete transcript set published by a contributor")
    func rejectNonConductorTranscriptPublisher() throws {
        var fixture = try makeFixture()
        try advanceToTranscriptAgreement(fixture: &fixture)
        let root = try Attempt.TranscriptRoot(
            validating: Array(repeating: 0x77, count: 32)
        )
        let message = try makeMessage(
            fixture: fixture,
            sequence: 3,
            phase: .transcriptAgreement,
            identifierByte: 0x98,
            sender: fixture.roster.contributors[0],
            fact: .transcriptAcknowledgementSet(
                MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                    for: fixture.roster.contributors,
                    binding: fixture.manifest,
                    transcriptRoot: root
                )
            )
        )

        let effects = fixture.session.apply(input: .authenticated(message))

        #expect(
            effects.first == .authenticatedInputRejected(
                .transcriptAcknowledgementPublisherIsNotConductor
            )
        )
        #expect(effects.allSatisfy { effect in
            if case .localAttempt(.bchSigningEligible) = effect {
                return false
            }
            return true
        })
        if case .terminal(.failed) = fixture.session.state {
            // Expected.
        } else {
            Issue.record("Expected non-conductor transcript publisher to terminate")
        }
    }

    @Test("Keep wallet-host results on their explicit provenance boundary")
    func rejectHostResultThatSkipsItsPhase() throws {
        var fixture = try makeFixture()

        let effects = fixture.session.apply(
            input: .hostResult(
                .signedTransactionValidated(
                    contributorSigners: fixture.roster.contributors
                )
            )
        )

        #expect(effects.contains { effect in
            if case .localAttempt(.attemptTerminated(.failed)) = effect {
                return true
            }
            return false
        })
        if case .terminal(.failed) = fixture.session.state {
            // Expected.
        } else {
            Issue.record("Expected phase skipping to terminate the attempt")
        }
    }

    @Test("Require a 32-byte authenticated message identifier")
    func requireMessageIdentifierWidth() {
        #expect(
            throws: RuntimeSession.MessageIdentifier.ValidationError
                .invalidByteCount(actual: 31)
        ) {
            _ = try RuntimeSession.MessageIdentifier(
                bytes: Array(repeating: 0, count: 31)
            )
        }
    }

    @Test("Guard anonymous one-time authorizations idempotently")
    func guardAnonymousAuthorizationsIdempotently() throws {
        var replay = OpalFusion.Mosaic.AnonymousReplayIndex()
        let authorization = OpalFusion.Mosaic.AnonymousReplayIndex
            .AuthorizationIdentifier(validatedBytes: [0x01])
        let first = try RuntimeSession.MessageIdentifier(
            bytes: Array(repeating: 0x10, count: 32)
        )
        let second = try RuntimeSession.MessageIdentifier(
            bytes: Array(repeating: 0x20, count: 32)
        )

        #expect(
            replay.record(
                authorization: authorization,
                messageIdentifier: first
            ) == .accepted
        )
        #expect(
            replay.record(
                authorization: authorization,
                messageIdentifier: first
            ) == .duplicate
        )
        #expect(
            replay.record(
                authorization: authorization,
                messageIdentifier: second
            ) == .conflict
        )
    }

    private func advanceToTranscriptAgreement(
        fixture: inout MosaicRuntimeSessionFixture
    ) throws {
        _ = fixture.session.apply(
            input: .authenticated(
                try makeManifestMessage(fixture: fixture, sequence: 0)
            )
        )
        _ = fixture.session.apply(
            input: .hostResult(
                .walletReservationsPrepared(
                    contributors: fixture.roster.contributors
                )
            )
        )
        _ = fixture.session.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 1,
                    phase: .groupedCommitment,
                    identifierByte: 0x92,
                    fact: .groupedCommitmentsValidated(
                        contributors: fixture.roster.contributors
                    )
                )
            )
        )
        _ = fixture.session.apply(
            input: .authenticated(
                try makeMessage(
                    fixture: fixture,
                    sequence: 2,
                    phase: .anonymousComponentSubmission,
                    identifierByte: 0x93,
                    fact: .anonymousComponentsValidated(
                        contributors: fixture.roster.contributors
                    )
                )
            )
        )
    }

    private func makeFixture() throws -> MosaicRuntimeSessionFixture {
        let roster = Self.fixtureRoster
        var attempt = Attempt(configuration: Self.fixtureConfiguration)
        _ = attempt.apply(input: .discoveryCompleted(candidateCount: 7))
        _ = attempt.apply(input: .candidateSetAgreementValidated)
        _ = attempt.apply(
            input: .controlRosterValidated(Self.fixtureRoleElection.controlRoster)
        )
        _ = attempt.apply(
            input: .roleCommitmentsReceived(
                Self.fixtureRoleElection.commitments
            )
        )
        _ = attempt.apply(
            input: .roleElectionValidated(
                Self.fixtureRoleElection.validation
            )
        )
        let attemptIdentifier = LocalAttempt.AttemptIdentifier(
            validatedBytes: [0xA1]
        )
        let generationIdentifier = LocalAttempt.GenerationIdentifier(
            opaqueBytes: [0xB2]
        )
        let localAttempt = try LocalAttempt(
            validatedAttempt: attempt,
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            materialIdentifier: .init(opaqueBytes: [0xC3]),
            localControlIdentity: roster.contributors[0]
        )
        return try MosaicRuntimeSessionFixture(
            session: .init(localAttempt: localAttempt),
            roster: roster,
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            manifest: Self.fixtureManifest
        )
    }

    private static let fixtureConfiguration = OpalFusion.Mosaic.Configuration(
        profile: .opalV0
    )

    private static let fixtureRoleElection = try! MosaicRoleElectionFixtures.makeElection(
        controlIdentities: (0 ..< 7).map { index in
            MosaicManifestSignatureFixtures.controlIdentity(
                scalarByte: UInt8(index + 1)
            )
        },
        profile: fixtureConfiguration.profile
    )

    private static let fixtureRoster = fixtureRoleElection.result.roster

    private static let fixtureManifest = try! Attempt.ManifestBinding(
        validatedRoundIdentifier: Array(repeating: 0xD4, count: 32),
        validatedManifestDigest: Array(repeating: 0xD5, count: 32)
    )

    private static let fixtureManifestSignatures =
        MosaicManifestSignatureFixtures.manifestSignatures(
            for: fixtureRoster,
            binding: fixtureManifest
        )

    private func makeManifestMessage(
        fixture: MosaicRuntimeSessionFixture,
        sequence: UInt64,
        identifierByte: UInt8 = 0x91,
        phase: Attempt.Phase = .manifestAgreement
    ) throws -> RuntimeSession.AuthenticatedMessage {
        try makeMessage(
            fixture: fixture,
            sequence: sequence,
            phase: phase,
            identifierByte: identifierByte,
            fact: .manifestSignatureSet(
                binding: fixture.manifest,
                signatures: Self.fixtureManifestSignatures
            )
        )
    }

    private func makeMessage(
        fixture: MosaicRuntimeSessionFixture,
        sequence: UInt64,
        phase: Attempt.Phase,
        identifierByte: UInt8,
        sender: Attempt.ControlIdentity? = nil,
        fact: RuntimeSession.AuthenticatedFact
    ) throws -> RuntimeSession.AuthenticatedMessage {
        .init(
            attemptIdentifier: fixture.attemptIdentifier,
            generationIdentifier: fixture.generationIdentifier,
            sender: sender ?? fixture.roster.conductor,
            sequence: sequence,
            phase: phase,
            messageIdentifier: try .init(
                bytes: Array(repeating: identifierByte, count: 32)
            ),
            authenticatedFact: fact
        )
    }
}
