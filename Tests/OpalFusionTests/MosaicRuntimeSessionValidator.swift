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
            fact: .transcriptAgreementValidated(
                fixture.roster.contributors.map {
                    .init(
                        contributor: $0,
                        transcriptRoot: .init(validatedBytes: [0x55])
                    )
                }
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

    private func makeFixture() throws -> MosaicRuntimeSessionFixture {
        let roster = try Attempt.Roster(
            members: (0 ..< 7).map { index in
                .init(
                    controlIdentity: .init(validatedBytes: [UInt8(index + 1)]),
                    role: index == 0 ? .conductor : .contributor
                )
            }
        )
        var attempt = Attempt()
        _ = attempt.apply(input: .discoveryCompleted(candidateCount: 7))
        _ = attempt.apply(input: .candidateSetAgreementValidated)
        _ = attempt.apply(
            input: .controlRosterValidated(roster.controlIdentities)
        )
        _ = attempt.apply(input: .rolesSelected(roster))
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
            manifest: try .init(
                validatedRoundIdentifier: Array(repeating: 0xD4, count: 32),
                validatedManifestDigest: Array(repeating: 0xD5, count: 32)
            )
        )
    }

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
            fact: .manifestSignaturesValidated(
                fixture.roster.controlIdentities.map {
                    .init(signer: $0, binding: fixture.manifest)
                }
            )
        )
    }

    private func makeMessage(
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
}
