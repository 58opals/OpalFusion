// MosaicMainnetAlphaAdmissionLedgerValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha admission ledger validation")
struct MosaicMainnetAlphaAdmissionLedgerValidator {
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Ledger = Alpha.AdmissionLedger

    @Test("Require exact roster sequence baselines and a local roster member")
    func validateInitialization() throws {
        let conductorHarness = try Fixture.makeHarness(localRole: .conductor)
        #expect(conductorHarness.ledger.state == .active(.manifestAgreement))

        var incompleteSequences = Dictionary(
            uniqueKeysWithValues: conductorHarness.election.result.roster
                .controlIdentities.map { ($0, UInt64(0)) }
        )
        incompleteSequences.removeValue(
            forKey: conductorHarness.election.result.roster.contributors[0]
        )
        #expect(throws: Ledger.InitializationError.controlSequenceRosterMismatch) {
            _ = try Ledger(
                attemptIdentifier: conductorHarness.attemptIdentifier,
                generationIdentifier: conductorHarness.generationIdentifier,
                localControlIdentity: conductorHarness.localControlIdentity,
                proposalValidation: conductorHarness.proposalValidation,
                expectedFirstControlSequenceBySender: incompleteSequences
            )
        }
        let unknownIdentity = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 254
        )
        #expect(
            throws: Ledger.InitializationError
                .localControlIdentityNotInRoster(unknownIdentity)
        ) {
            _ = try Ledger(
                attemptIdentifier: conductorHarness.attemptIdentifier,
                generationIdentifier: conductorHarness.generationIdentifier,
                localControlIdentity: unknownIdentity,
                proposalValidation: conductorHarness.proposalValidation,
                expectedFirstControlSequenceBySender: Dictionary(
                    uniqueKeysWithValues: conductorHarness.election.result.roster
                        .controlIdentities.map { ($0, UInt64(0)) }
                )
            )
        }
    }

    @Test("Reject foreign routing without consuming the expected sequence")
    func rejectForeignRoutingBeforeReplay() throws {
        enum Mismatch: CaseIterable {
            case attempt
            case generation
            case outerIdentity
            case expiry
            case round
        }

        for mismatch in Mismatch.allCases {
            var harness = try Fixture.makeHarness(localRole: .contributor)
            let validRun = try manifestRun(harness: harness)
            let valid = validRun.reservation
            let rejected: Ledger.ControlDelivery
            let expectedFailure: Ledger.Failure
            switch mismatch {
            case .attempt:
                expectedFailure = .attemptIdentifierMismatch
                rejected = Fixture.controlDelivery(
                    envelope: valid.envelope,
                    harness: harness,
                    attemptIdentifier: .init(
                        validatedBytes: [UInt8](repeating: 0xB1, count: 32)
                    )
                )
            case .generation:
                expectedFailure = .generationIdentifierMismatch
                rejected = Fixture.controlDelivery(
                    envelope: valid.envelope,
                    harness: harness,
                    generationIdentifier: .init(
                        opaqueBytes: [UInt8](repeating: 0xB2, count: 32)
                    )
                )
            case .outerIdentity:
                expectedFailure = .outerEventIdentityMismatch
                rejected = Fixture.controlDelivery(
                    envelope: valid.envelope,
                    harness: harness,
                    authenticatedOuterEventIdentity:
                        [UInt8](repeating: 0, count: 32)
                )
            case .expiry:
                expectedFailure = .expiredEnvelope
                rejected = Fixture.controlDelivery(
                    envelope: valid.envelope,
                    harness: harness,
                    currentUnixSeconds: 1_800_000_061
                )
            case .round:
                expectedFailure = .foreignRound
                let foreignEnvelope = try Fixture.signedEnvelope(
                    sender: harness.election.result.roster.conductor,
                    phase: .manifestAgreement,
                    payloadType: valid.envelope.payloadType,
                    payload: valid.envelope.payload,
                    sequence: 0,
                    roundIdentifier: [UInt8](repeating: 0xCC, count: 32)
                )
                rejected = Fixture.controlDelivery(
                    envelope: foreignEnvelope,
                    harness: harness
                )
            }

            #expect(
                harness.ledger.apply(input: .control(rejected))
                    == [.inputRejected(expectedFailure)]
            )
            #expect(harness.ledger.state == .active(.manifestAgreement))
            #expect(
                harness.ledger.apply(input: .control(valid))
                    == [
                        .aggregateReservationAccepted(
                            sender: harness.election.result.roster.conductor,
                            kind: .completeManifest,
                            fragmentCount: validRun.fragments.count
                        )
                    ]
            )
        }
    }

    @Test("Reject a complete manifest whose core differs from the proposal")
    func rejectManifestCoreSubstitution() throws {
        var harness = try Fixture.makeHarness(localRole: .contributor)
        let substitutedManifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: harness.election,
            verificationKey: harness.manifest.core.blindSigningVerificationKey,
            relaySetDigest: [UInt8](repeating: 0x45, count: 32)
        )
        let run = try Fixture.aggregateRun(
            canonicalBytes: substitutedManifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: harness
        )

        let effects = Fixture.admit(run, to: &harness.ledger)
        #expect(
            effects.last
                == Ledger.Effect.attemptTerminated(
                    .failed(.completeManifestCoreMismatch)
                )
        )
    }

    @Test("Enforce strict replay, conflict, gap, stale, and overflow behavior")
    func enforceControlReplay() throws {
        var duplicateHarness = try Fixture.makeHarness(localRole: .contributor)
        let duplicateRun = try manifestRun(harness: duplicateHarness)
        let accepted = duplicateHarness.ledger.apply(
            input: .control(duplicateRun.reservation)
        )
        #expect(accepted.count == 1)
        #expect(
            duplicateHarness.ledger.apply(
                input: .control(duplicateRun.reservation)
            ) == [.exactDuplicateIgnored]
        )
        #expect(
            duplicateHarness.ledger.apply(
                input: .control(
                    Fixture.controlDelivery(
                        envelope: duplicateRun.reservation.envelope,
                        harness: duplicateHarness,
                        currentUnixSeconds: 1_800_000_061
                    )
                )
            ) == [.exactDuplicateIgnored]
        )
        let conflictingReservation = try Alpha.AggregateReservation(
            aggregateKind: .completeManifest,
            aggregateDigest: [UInt8](repeating: 0xED, count: 32),
            declaredCanonicalByteCount:
                duplicateHarness.manifest.canonicalBytes.count
        )
        let conflictEnvelope = try Fixture.signedEnvelope(
            sender: duplicateHarness.election.result.roster.conductor,
            phase: .manifestAgreement,
            payloadType: .aggregateReservation,
            payload: try Alpha.CanonicalWireCodec.encodeAggregateReservation(
                conflictingReservation
            ),
            sequence: 0,
            roundIdentifier: duplicateHarness.manifest.core.roundIdentifier
        )
        let conflict = duplicateHarness.ledger.apply(
            input: .control(
                Fixture.controlDelivery(
                    envelope: conflictEnvelope,
                    harness: duplicateHarness,
                    currentUnixSeconds: 1_800_000_061
                )
            )
        )
        #expect(
            conflict == [
                .attemptTerminated(
                    .failed(
                        .sequenceConflict(
                            sender: duplicateHarness.election.result.roster
                                .conductor,
                            sequence: 0
                        )
                    )
                )
            ]
        )

        var gapHarness = try Fixture.makeHarness(localRole: .contributor)
        let gapRun = try Fixture.aggregateRun(
            canonicalBytes: gapHarness.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: gapHarness.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 1,
            harness: gapHarness
        )
        #expect(
            gapHarness.ledger.apply(input: .control(gapRun.reservation))
                == [
                    .attemptTerminated(
                        .failed(.sequenceGap(expected: 0, received: 1))
                    )
                ]
        )

        var staleHarness = try Fixture.makeHarness(
            localRole: .contributor,
            firstSequence: 1
        )
        let staleRun = try Fixture.aggregateRun(
            canonicalBytes: staleHarness.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: staleHarness.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: staleHarness
        )
        #expect(
            staleHarness.ledger.apply(input: .control(staleRun.reservation))
                == [
                    .inputRejected(.staleSequence(expected: 1, received: 0))
                ]
        )
        let correctedRun = try Fixture.aggregateRun(
            canonicalBytes: staleHarness.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: staleHarness.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 1,
            harness: staleHarness
        )
        #expect(
            staleHarness.ledger.apply(input: .control(correctedRun.reservation))
                .count == 1
        )

        var overflowHarness = try Fixture.makeHarness(
            localRole: .contributor,
            firstSequence: UInt64.max
        )
        let overflowReservation = try Alpha.AggregateReservation(
            aggregateKind: .completeManifest,
            aggregateDigest: Alpha.RoleSeedValidator.hash(
                domainSuffix: Alpha.AggregateKind.completeManifest
                    .digestDomainSuffix,
                fields: [overflowHarness.manifest.canonicalBytes]
            ),
            declaredCanonicalByteCount:
                overflowHarness.manifest.canonicalBytes.count
        )
        let overflowEnvelope = try Fixture.signedEnvelope(
            sender: overflowHarness.election.result.roster.conductor,
            phase: .manifestAgreement,
            payloadType: .aggregateReservation,
            payload: try Alpha.CanonicalWireCodec.encodeAggregateReservation(
                overflowReservation
            ),
            sequence: UInt64.max,
            roundIdentifier: overflowHarness.manifest.core.roundIdentifier
        )
        #expect(
            overflowHarness.ledger.apply(
                input: .control(
                    Fixture.controlDelivery(
                        envelope: overflowEnvelope,
                        harness: overflowHarness
                    )
                )
            ) == [
                .attemptTerminated(
                    .failed(
                        .sequenceExhausted(
                            sender: overflowHarness.election.result.roster
                                .conductor
                        )
                    )
                )
            ]
        )
    }

    @Test("Reject phase skipping, rollback, and advancing an active fragment run")
    func enforcePhaseSynchronization() throws {
        var missingManifest = try Fixture.makeHarness(localRole: .contributor)
        #expect(
            try synchronize(
                &missingManifest.ledger,
                to: .walletReservation
            )
                == [
                    .attemptTerminated(
                        .failed(
                            .phaseAdvancePrerequisiteMissing(.walletReservation)
                        )
                    )
                ]
        )

        var activeRun = try Fixture.makeHarness(localRole: .contributor)
        let run = try manifestRun(harness: activeRun)
        _ = activeRun.ledger.apply(input: .control(run.reservation))
        #expect(
            try synchronize(&activeRun.ledger, to: .walletReservation)
                == [
                    .attemptTerminated(
                        .failed(.activeAggregateRunPreventsPhaseAdvance)
                    )
                ]
        )

        var skipping = try Fixture.makeHarness(localRole: .contributor)
        _ = Fixture.admit(try manifestRun(harness: skipping), to: &skipping.ledger)
        #expect(
            try synchronize(&skipping.ledger, to: .groupedCommitment)
                == [
                    .attemptTerminated(
                        .failed(
                            .invalidPhaseTransition(
                                from: .manifestAgreement,
                                to: .groupedCommitment
                            )
                        )
                    )
                ]
        )

        var rollback = try Fixture.makeHarness(localRole: .contributor)
        _ = Fixture.admit(try manifestRun(harness: rollback), to: &rollback.ledger)
        _ = try synchronize(&rollback.ledger, to: .walletReservation)
        #expect(
            try synchronize(&rollback.ledger, to: .manifestAgreement)
                == [
                    .attemptTerminated(
                        .failed(
                            .invalidPhaseTransition(
                                from: .walletReservation,
                                to: .manifestAgreement
                            )
                        )
                    )
                ]
        )

        var routing = try Fixture.makeHarness(localRole: .contributor)
        let routingRequest = try #require(
            routing.ledger.phaseTransitionRequest(to: .walletReservation)
        )
        let foreignAttemptRequest = Ledger.PhaseTransitionRequest(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xB3, count: 32)
            ),
            generationIdentifier: routingRequest.generationIdentifier,
            from: routingRequest.from,
            to: routingRequest.to
        )
        #expect(
            routing.ledger.synchronize(
                using: try transitionValidation(foreignAttemptRequest)
            ) == [.inputRejected(.attemptIdentifierMismatch)]
        )
        let foreignGenerationRequest = Ledger.PhaseTransitionRequest(
            attemptIdentifier: routingRequest.attemptIdentifier,
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xB4, count: 32)
            ),
            from: routingRequest.from,
            to: routingRequest.to
        )
        #expect(
            routing.ledger.synchronize(
                using: try transitionValidation(foreignGenerationRequest)
            ) == [.inputRejected(.generationIdentifierMismatch)]
        )
        #expect(throws: RejectingPhaseTransitionValidator.Rejection.self) {
            _ = try Ledger.PhaseTransitionValidation(
                validating: routingRequest,
                using: RejectingPhaseTransitionValidator()
            )
        }
        #expect(routing.ledger.state == .active(.manifestAgreement))

        var stale = try Fixture.makeHarness(localRole: .contributor)
        _ = Fixture.admit(try manifestRun(harness: stale), to: &stale.ledger)
        let staleRequest = try #require(
            stale.ledger.phaseTransitionRequest(to: .walletReservation)
        )
        let staleValidation = try transitionValidation(staleRequest)
        #expect(
            stale.ledger.synchronize(using: staleValidation)
                == [.phaseAdvanced(.walletReservation)]
        )
        #expect(
            stale.ledger.synchronize(using: staleValidation)
                == [
                    .attemptTerminated(
                        .failed(.phaseTransitionValidationMismatch)
                    )
                ]
        )
    }

    @Test("Isolate concurrent aggregate runs by authenticated sender")
    func isolateAggregateRunsBySender() throws {
        var concurrentHarness = try Fixture.makeHarness(localRole: .conductor)
        _ = try admitManifestAndAdvanceWallet(harness: &concurrentHarness)
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: concurrentHarness.election.result.roster,
            manifest: concurrentHarness.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let commits = try Fixture.makePlayerCommits(
            harness: concurrentHarness,
            commitmentSet: preparation.commitmentSet
        )
        let firstRun = try Fixture.aggregateRun(
            canonicalBytes: commits[0].canonicalBytes,
            kind: .playerCommit,
            sender: commits[0].contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: concurrentHarness
        )
        let secondRun = try Fixture.aggregateRun(
            canonicalBytes: commits[1].canonicalBytes,
            kind: .playerCommit,
            sender: commits[1].contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: concurrentHarness
        )

        #expect(
            concurrentHarness.ledger.apply(input: .control(firstRun.reservation))
                .count == 1
        )
        #expect(
            concurrentHarness.ledger.apply(input: .control(secondRun.reservation))
                .count == 1
        )
        var completed: Set<Ledger.ControlIdentity> = []
        for index in 0 ..< max(
            firstRun.fragments.count,
            secondRun.fragments.count
        ) {
            for (run, contributor) in [
                (firstRun, commits[0].contributor),
                (secondRun, commits[1].contributor),
            ] where index < run.fragments.count {
                let effects = concurrentHarness.ledger.apply(
                    input: .control(run.fragments[index])
                )
                if effects.contains(.playerCommitAdmitted(
                    contributor == commits[0].contributor
                        ? commits[0] : commits[1]
                )) {
                    completed.insert(contributor)
                }
            }
        }
        #expect(completed == Set([commits[0].contributor, commits[1].contributor]))
        #expect(concurrentHarness.ledger.state == .active(.walletReservation))

        var interleavingHarness = try Fixture.makeHarness(localRole: .conductor)
        _ = try admitManifestAndAdvanceWallet(harness: &interleavingHarness)
        let interleavingPreparation = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: interleavingHarness.election.result.roster,
                manifest: interleavingHarness.manifest.binding,
                profile: .opalMainnetAlpha
            )
        let commit = try Fixture.makePlayerCommits(
            harness: interleavingHarness,
            commitmentSet: interleavingPreparation.commitmentSet
        )[0]
        let activeRun = try Fixture.aggregateRun(
            canonicalBytes: commit.canonicalBytes,
            kind: .playerCommit,
            sender: commit.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: interleavingHarness
        )
        let conflictingRun = try Fixture.aggregateRun(
            canonicalBytes: commit.canonicalBytes,
            kind: .playerCommit,
            sender: commit.contributor,
            phase: .walletReservation,
            sequence: 1,
            harness: interleavingHarness
        )
        _ = interleavingHarness.ledger.apply(
            input: .control(activeRun.reservation)
        )
        #expect(
            interleavingHarness.ledger.apply(
                input: .control(conflictingRun.reservation)
            ) == [
                .attemptTerminated(
                    .failed(.aggregateInterleaving(sender: commit.contributor))
                )
            ]
        )
    }

    @Test("Terminate when a reassembled aggregate has the wrong digest")
    func rejectMalformedReassembly() throws {
        var harness = try Fixture.makeHarness(localRole: .contributor)
        let run = try manifestRun(harness: harness)
        _ = harness.ledger.apply(input: .control(run.reservation))
        for fragment in run.fragments.dropLast() {
            _ = harness.ledger.apply(input: .control(fragment))
        }

        let reservation = try Alpha.CanonicalWireCodec
            .decodeAggregateReservation(from: run.reservation.envelope.payload)
        let lastDelivery = try #require(run.fragments.last)
        let lastFragment = try Alpha.CanonicalWireCodec.decodeAggregateFragment(
            from: lastDelivery.envelope.payload,
            reservation: reservation
        )
        var corruptedBody = lastFragment.body
        corruptedBody[corruptedBody.startIndex] ^= 0x01
        let corruptedFragment = try Alpha.AggregateFragment(
            reservationSequence: lastFragment.reservationSequence,
            fragmentIndex: lastFragment.fragmentIndex,
            body: corruptedBody,
            reservation: reservation
        )
        let corruptedEnvelope = try Fixture.signedEnvelope(
            sender: harness.election.result.roster.conductor,
            phase: .manifestAgreement,
            payloadType: .aggregateFragment,
            payload: try Alpha.CanonicalWireCodec.encodeAggregateFragment(
                corruptedFragment
            ),
            sequence: lastDelivery.envelope.sequence,
            roundIdentifier: harness.manifest.core.roundIdentifier
        )
        #expect(
            harness.ledger.apply(
                input: .control(
                    Fixture.controlDelivery(
                        envelope: corruptedEnvelope,
                        harness: harness
                    )
                )
            ) == [
                .attemptTerminated(
                    .failed(.aggregateReassemblyFailed(.payloadDigestMismatch))
                )
            ]
        )
    }

    @Test(
        "Require one PlayerCommit from every contributor",
        arguments: [7, 8, 9]
    )
    func requirePlayerCommitUnanimity(candidateCount: Int) throws {
        var harness = try Fixture.makeHarness(
            candidateCount: candidateCount,
            localRole: .conductor
        )
        let conductorNextSequence = try admitManifestAndAdvanceWallet(
            harness: &harness
        )
        #expect(conductorNextSequence > 0)
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.election.result.roster,
            manifest: harness.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let commits = try Fixture.makePlayerCommits(
            harness: harness,
            commitmentSet: preparation.commitmentSet
        ).reversed()
        var finalUnanimity: [Alpha.PlayerCommit]?
        var submittedCount = 0
        for commit in commits {
            let run = try Fixture.aggregateRun(
                canonicalBytes: commit.canonicalBytes,
                kind: .playerCommit,
                sender: commit.contributor,
                phase: .walletReservation,
                sequence: 0,
                harness: harness
            )
            let effects = Fixture.admit(run, to: &harness.ledger)
            submittedCount += 1
            for effect in effects {
                if case let .playerCommitUnanimityReached(values) = effect {
                    finalUnanimity = values
                }
            }
            if submittedCount < harness.election.result.roster.contributors.count {
                #expect(finalUnanimity == nil)
            }
        }
        let unanimity = try #require(finalUnanimity)
        #expect(unanimity.count == candidateCount - 1)
        #expect(
            unanimity.map(\.contributor) == unanimity.map(\.contributor).sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
        )
    }

    @Test("Reject a second logical PlayerCommit from one contributor")
    func rejectPlayerCommitSlotReuse() throws {
        var harness = try Fixture.makeHarness(localRole: .conductor)
        _ = try admitManifestAndAdvanceWallet(harness: &harness)
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.election.result.roster,
            manifest: harness.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let commit = try Fixture.makePlayerCommits(
            harness: harness,
            commitmentSet: preparation.commitmentSet
        )[0]
        let firstRun = try Fixture.aggregateRun(
            canonicalBytes: commit.canonicalBytes,
            kind: .playerCommit,
            sender: commit.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: harness
        )
        _ = Fixture.admit(firstRun, to: &harness.ledger)
        let secondRun = try Fixture.aggregateRun(
            canonicalBytes: commit.canonicalBytes,
            kind: .playerCommit,
            sender: commit.contributor,
            phase: .walletReservation,
            sequence: firstRun.nextSequence,
            harness: harness
        )
        let effects = Fixture.admit(secondRun, to: &harness.ledger)
        #expect(
            effects.last == .attemptTerminated(
                .failed(.conflictingDocument(.playerCommit(commit.contributor)))
            )
        )
    }

    @Test("Bind a conductor commitment set to every admitted PlayerCommit")
    func bindCommitmentSetToPlayerCommits() throws {
        var harness = try Fixture.makeHarness(localRole: .conductor)
        let prepared = try prepareConductorCommitments(harness: &harness)
        var commitments = prepared.preparation.commitmentSet.commitments
        let first = commitments[0]
        var substitutedDigest = first.saltedComponentDigest
        substitutedDigest[substitutedDigest.startIndex] ^= 0x01
        commitments[0] = try OpalFusion.Mosaic.OpalV0.ComponentCommitment(
            saltedComponentDigest: substitutedDigest,
            amountCommitment: first.amountCommitment,
            communicationPublicKey: first.communicationPublicKey
        )
        let substituted = try OpalFusion.Mosaic.OpalV0.CommitmentSet(
            profile: .opalMainnetAlpha,
            commitments: commitments
        )
        let run = try Fixture.aggregateRun(
            canonicalBytes: substituted.canonicalBytes,
            kind: .commitmentSet,
            sender: harness.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: prepared.nextConductorSequence,
            harness: harness
        )
        #expect(
            Fixture.admit(run, to: &harness.ledger).last
                == .attemptTerminated(
                    .failed(.commitmentSetDoesNotMatchPlayerCommits)
                )
        )
    }

    @Test("Keep contributor admission closed before the acknowledgement-set contract")
    func keepContributorSigningGateClosed() throws {
        var harness = try Fixture.makeHarness(localRole: .contributor)
        let prepared = try prepareTranscript(harness: &harness)
        #expect(
            try synchronize(
                &harness.ledger,
                to: .transcriptAgreement(prepared.transcript)
            ) == [.phaseAdvanced(.transcriptAgreement(prepared.transcript))]
        )

        let contributor = harness.election.result.roster.contributors[0]
        let acknowledgement = try #require(
            MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                for: [contributor],
                binding: harness.manifest.binding,
                transcriptRoot: prepared.transcript.transcriptRoot,
                profile: .opalMainnetAlpha
            ).first
        )
        let envelope = try Fixture.signedEnvelope(
            sender: contributor,
            phase: .transcriptAgreement,
            payloadType: .preSignAcknowledgement,
            payload: try Alpha.CanonicalWireCodec
                .encodePreSignAcknowledgementSubmission(
                    roundIdentifier: acknowledgement.roundIdentifier,
                    transcriptRoot: acknowledgement.transcriptRoot,
                    signature: acknowledgement.rawRepresentation
                ),
            sequence: 0,
            roundIdentifier: harness.manifest.core.roundIdentifier
        )
        #expect(
            harness.ledger.apply(
                input: .control(
                    Fixture.controlDelivery(envelope: envelope, harness: harness)
                )
            ) == [
                .inputRejected(.preSignAcknowledgementAdmissionUnavailable)
            ]
        )
        #expect(
            try synchronize(
                &harness.ledger,
                to: .bchSigning(prepared.transcript)
            ) == [
                .attemptTerminated(.failed(.bchSigningAdmissionUnavailable))
            ]
        )
    }

    @Test("Keep anonymous BCH signatures closed and terminal state absorbing")
    func keepDeferredAndTerminalBehaviorClosed() throws {
        var harness = try Fixture.makeHarness(localRole: .conductor)
        let staleManifestRun = try manifestRun(harness: harness)
        let communicationKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 1_801).compressed
        let anonymousEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: harness.manifest.core.roundIdentifier,
            phase: .bchSigning,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: Fixture.eventIdentity(scalarByte: 250),
            sequence: 0,
            payloadType: .bchSignatureSubmission,
            expiryUnixSeconds: 1_800_000_060,
            payload: [0xAA]
        )
        let anonymousDelivery = Ledger.AnonymousComponentDelivery(
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            envelope: anonymousEnvelope,
            authenticatedOuterEventIdentity: Array(communicationKey.dropFirst()),
            authenticatedRecipientEventIdentity:
                anonymousEnvelope.recipientEventIdentity,
            authenticatedMessageIdentifier: try .init(
                bytes: [UInt8](repeating: 0xE1, count: 32)
            ),
            currentUnixSeconds: 1_800_000_000
        )
        #expect(
            harness.ledger.receiveAnonymousComponent(
                anonymousDelivery,
                using: RejectingAnonymousComponentValidator()
            ) == [.inputRejected(.unsupportedAnonymousBCHSignature)]
        )

        #expect(
            harness.ledger.apply(input: .retryRequested)
                == [
                    .attemptTerminated(.failed(.inPlaceRetryNotPermitted))
                ]
        )
        #expect(
            harness.ledger.apply(input: .cancel)
                == [.inputRejected(.inputAfterTermination)]
        )
        let freshAttempt = Ledger.AttemptIdentifier(
            validatedBytes: [UInt8](repeating: 0xF1, count: 32)
        )
        let freshGeneration = Ledger.GenerationIdentifier(
            opaqueBytes: [UInt8](repeating: 0xF2, count: 32)
        )
        var freshLedger = try Ledger(
            attemptIdentifier: freshAttempt,
            generationIdentifier: freshGeneration,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation,
            expectedFirstControlSequenceBySender: Dictionary(
                uniqueKeysWithValues: harness.election.result.roster
                    .controlIdentities.map { ($0, UInt64(0)) }
            )
        )
        #expect(
            freshLedger.apply(input: .control(staleManifestRun.reservation))
                == [.inputRejected(.attemptIdentifierMismatch)]
        )
        let freshDelivery = Fixture.controlDelivery(
            envelope: staleManifestRun.reservation.envelope,
            harness: harness,
            attemptIdentifier: freshAttempt,
            generationIdentifier: freshGeneration
        )
        #expect(
            freshLedger.apply(input: .control(freshDelivery))
                == [
                    .aggregateReservationAccepted(
                        sender: harness.election.result.roster.conductor,
                        kind: .completeManifest,
                        fragmentCount: staleManifestRun.fragments.count
                    )
                ]
        )
    }

    @Test("Admit authorized components only at the local conductor")
    func admitAnonymousComponentsAtConductorOnly() throws {
        let evaluator = try OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
            .generate()
        let verificationKey = try #require(evaluator.verificationKey)
        var conductorHarness = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: verificationKey
        )
        let prepared = try prepareConductorCommitments(
            harness: &conductorHarness
        )
        let commitmentRun = try Fixture.aggregateRun(
            canonicalBytes: prepared.preparation.commitmentSet.canonicalBytes,
            kind: .commitmentSet,
            sender: conductorHarness.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: prepared.nextConductorSequence,
            harness: conductorHarness
        )
        _ = Fixture.admit(commitmentRun, to: &conductorHarness.ledger)
        #expect(
            try synchronize(
                &conductorHarness.ledger,
                to: .anonymousComponentSubmission
            )
                == [.phaseAdvanced(.anonymousComponentSubmission)]
        )

        let authorizationInput = try OpalFusion.Mosaic.OpalV0
            .AuthorizationTokenInput(
                profile: .opalMainnetAlpha,
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                keyIdentifier: [UInt8](verificationKey.keyIdentifier),
                nonce: [UInt8](repeating: 0x91, count: 32)
            )
        let authorizationRequest = try OpalFusion.Mosaic.OpalV0
            .AuthorizationRequest(
                input: authorizationInput,
                using: verificationKey
            )
        let authorizationToken = try authorizationRequest.finalize(
            evaluator.evaluate(authorizationRequest.blindedMessage)
        )
        let componentPayload = try OpalFusion.Mosaic.OpalV0
            .AnonymousComponentPayload(
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                authorizationToken: authorizationToken,
                component: prepared.preparation.componentSet.components[0]
            )
        let communicationKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 1_802).compressed
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: Fixture.eventIdentity(scalarByte: 250),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_060,
            payload: try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                .encodeAnonymousComponent(componentPayload)
        )
        let messageIdentifier = try OpalFusion.Mosaic.RuntimeSession
            .MessageIdentifier(bytes: [UInt8](repeating: 0xE2, count: 32))
        let delivery = Ledger.AnonymousComponentDelivery(
            attemptIdentifier: conductorHarness.attemptIdentifier,
            generationIdentifier: conductorHarness.generationIdentifier,
            envelope: envelope,
            authenticatedOuterEventIdentity: Array(communicationKey.dropFirst()),
            authenticatedRecipientEventIdentity: envelope.recipientEventIdentity,
            authenticatedMessageIdentifier: messageIdentifier,
            currentUnixSeconds: 1_800_000_000
        )
        var messageConflictLedger = conductorHarness.ledger
        var recipientReuseLedger = conductorHarness.ledger
        var communicationKeyReuseLedger = conductorHarness.ledger
        let accepted = conductorHarness.ledger.receiveAnonymousComponent(
            delivery,
            using: AcceptingAnonymousComponentValidator()
        )
        _ = messageConflictLedger.receiveAnonymousComponent(
            delivery,
            using: AcceptingAnonymousComponentValidator()
        )
        _ = recipientReuseLedger.receiveAnonymousComponent(
            delivery,
            using: AcceptingAnonymousComponentValidator()
        )
        _ = communicationKeyReuseLedger.receiveAnonymousComponent(
            delivery,
            using: AcceptingAnonymousComponentValidator()
        )
        #expect(accepted.count == 1)
        guard case .anonymousComponentAdmitted = accepted[0] else {
            Issue.record("Expected one admitted anonymous component")
            return
        }
        #expect(
            conductorHarness.ledger.receiveAnonymousComponent(
                delivery,
                using: RejectingAnonymousComponentValidator()
            ) == [.exactDuplicateIgnored]
        )

        let conflictingEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: Fixture.eventIdentity(scalarByte: 250),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_059,
            payload: try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                .encodeAnonymousComponent(componentPayload)
        )
        #expect(
            messageConflictLedger.receiveAnonymousComponent(
                .init(
                    attemptIdentifier: conductorHarness.attemptIdentifier,
                    generationIdentifier: conductorHarness.generationIdentifier,
                    envelope: conflictingEnvelope,
                    authenticatedOuterEventIdentity:
                        Array(communicationKey.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        conflictingEnvelope.recipientEventIdentity,
                    authenticatedMessageIdentifier: messageIdentifier,
                    currentUnixSeconds: 1_800_000_000
                ),
                using: AcceptingAnonymousComponentValidator()
            ) == [.attemptTerminated(.failed(.anonymousMessageConflict))]
        )

        let secondAuthorizationInput = try OpalFusion.Mosaic.OpalV0
            .AuthorizationTokenInput(
                profile: .opalMainnetAlpha,
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                keyIdentifier: [UInt8](verificationKey.keyIdentifier),
                nonce: [UInt8](repeating: 0x92, count: 32)
            )
        let secondAuthorizationRequest = try OpalFusion.Mosaic.OpalV0
            .AuthorizationRequest(
                input: secondAuthorizationInput,
                using: verificationKey
            )
        let secondToken = try secondAuthorizationRequest.finalize(
            evaluator.evaluate(secondAuthorizationRequest.blindedMessage)
        )
        let secondPayload = try OpalFusion.Mosaic.OpalV0
            .AnonymousComponentPayload(
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                authorizationToken: secondToken,
                component: prepared.preparation.componentSet.components[1]
            )
        let secondCommunicationKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 1_803).compressed
        let reusedRecipientEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: secondCommunicationKey,
            recipientEventIdentity: envelope.recipientEventIdentity,
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_060,
            payload: try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                .encodeAnonymousComponent(secondPayload)
        )
        #expect(
            recipientReuseLedger.receiveAnonymousComponent(
                .init(
                    attemptIdentifier: conductorHarness.attemptIdentifier,
                    generationIdentifier: conductorHarness.generationIdentifier,
                    envelope: reusedRecipientEnvelope,
                    authenticatedOuterEventIdentity:
                        Array(secondCommunicationKey.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        reusedRecipientEnvelope.recipientEventIdentity,
                    authenticatedMessageIdentifier: try .init(
                        bytes: [UInt8](repeating: 0xE4, count: 32)
                    ),
                    currentUnixSeconds: 1_800_000_000
                ),
                using: AcceptingAnonymousComponentValidator()
            ) == [
                .attemptTerminated(.failed(.anonymousRecipientIdentityReuse))
            ]
        )

        let reusedCommunicationKeyEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: Fixture.eventIdentity(scalarByte: 249),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_060,
            payload: try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                .encodeAnonymousComponent(secondPayload)
        )
        #expect(
            communicationKeyReuseLedger.receiveAnonymousComponent(
                .init(
                    attemptIdentifier: conductorHarness.attemptIdentifier,
                    generationIdentifier: conductorHarness.generationIdentifier,
                    envelope: reusedCommunicationKeyEnvelope,
                    authenticatedOuterEventIdentity:
                        Array(communicationKey.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        reusedCommunicationKeyEnvelope.recipientEventIdentity,
                    authenticatedMessageIdentifier: try .init(
                        bytes: [UInt8](repeating: 0xE5, count: 32)
                    ),
                    currentUnixSeconds: 1_800_000_000
                ),
                using: AcceptingAnonymousComponentValidator()
            ) == [
                .attemptTerminated(.failed(.anonymousCommunicationKeyReuse))
            ]
        )

        let conflictingDelivery = Ledger.AnonymousComponentDelivery(
            attemptIdentifier: conductorHarness.attemptIdentifier,
            generationIdentifier: conductorHarness.generationIdentifier,
            envelope: envelope,
            authenticatedOuterEventIdentity: Array(communicationKey.dropFirst()),
            authenticatedRecipientEventIdentity: envelope.recipientEventIdentity,
            authenticatedMessageIdentifier: try .init(
                bytes: [UInt8](repeating: 0xE3, count: 32)
            ),
            currentUnixSeconds: 1_800_000_000
        )
        #expect(
            conductorHarness.ledger.receiveAnonymousComponent(
                conflictingDelivery,
                using: AcceptingAnonymousComponentValidator()
            ) == [
                .attemptTerminated(.failed(.anonymousAuthorizationConflict))
            ]
        )
        #expect(
            conductorHarness.ledger.receiveAnonymousComponent(
                delivery,
                using: AcceptingAnonymousComponentValidator()
            ) == [.exactDuplicateIgnored]
        )

        var contributorHarness = try Fixture.makeHarness(localRole: .contributor)
        _ = try prepareTranscript(harness: &contributorHarness)
        #expect(
            contributorHarness.ledger.receiveAnonymousComponent(
                .init(
                    attemptIdentifier: contributorHarness.attemptIdentifier,
                    generationIdentifier: contributorHarness.generationIdentifier,
                    envelope: envelope,
                    authenticatedOuterEventIdentity:
                        Array(communicationKey.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        envelope.recipientEventIdentity,
                    authenticatedMessageIdentifier: messageIdentifier,
                    currentUnixSeconds: 1_800_000_000
                ),
                using: AcceptingAnonymousComponentValidator()
            ) == [.inputRejected(.anonymousComponentAdmissionUnavailable)]
        )
    }

    @Test(
        "Collect conductor acknowledgements without authorizing BCH signing",
        .timeLimit(.minutes(2))
    )
    func collectConductorAcknowledgementsWithoutSigning() throws {
        let evaluator = try OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
            .generate()
        let verificationKey = try #require(evaluator.verificationKey)
        var harness = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: verificationKey
        )
        let prepared = try prepareConductorCommitments(harness: &harness)
        let commitmentRun = try Fixture.aggregateRun(
            canonicalBytes: prepared.preparation.commitmentSet.canonicalBytes,
            kind: .commitmentSet,
            sender: harness.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: prepared.nextConductorSequence,
            harness: harness
        )
        _ = Fixture.admit(commitmentRun, to: &harness.ledger)
        #expect(
            try synchronize(
                &harness.ledger,
                to: .anonymousComponentSubmission
            ) == [.phaseAdvanced(.anonymousComponentSubmission)]
        )

        for (index, component) in prepared.preparation.componentSet.components
            .enumerated() {
            let authorizationInput = try OpalFusion.Mosaic.OpalV0
                .AuthorizationTokenInput(
                    profile: .opalMainnetAlpha,
                    roundIdentifier: harness.manifest.core.roundIdentifier,
                    keyIdentifier: [UInt8](verificationKey.keyIdentifier),
                    nonce: MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(20_000 + index)
                )
            let request = try OpalFusion.Mosaic.OpalV0.AuthorizationRequest(
                input: authorizationInput,
                using: verificationKey
            )
            let blindSignature: OpalCrypto.RSABSSA.BlindSignature
            do {
                blindSignature = try evaluator.evaluate(request.blindedMessage)
            } catch {
                Issue.record(
                    "RSABSSA evaluation failed at component \(index): \(error)"
                )
                return
            }
            let token = try request.finalize(blindSignature)
            let payload = try OpalFusion.Mosaic.OpalV0
                .AnonymousComponentPayload(
                    roundIdentifier: harness.manifest.core.roundIdentifier,
                    authorizationToken: token,
                    component: component
                )
            let communicationKey = try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 2_000 + index).compressed
            let recipientEventIdentity = Fixture.eventIdentity(
                scalarByte: UInt8(20 + index)
            )
            let envelope = try Alpha.AnonymousEnvelope(
                roundIdentifier: harness.manifest.core.roundIdentifier,
                phase: .anonymousComponentSubmission,
                senderCommunicationPublicKey: communicationKey,
                recipientEventIdentity: recipientEventIdentity,
                sequence: 0,
                payloadType: .anonymousComponent,
                expiryUnixSeconds: 1_800_000_060,
                payload: try OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
                    .encodeAnonymousComponent(payload)
            )
            let effects = harness.ledger.receiveAnonymousComponent(
                .init(
                    attemptIdentifier: harness.attemptIdentifier,
                    generationIdentifier: harness.generationIdentifier,
                    envelope: envelope,
                    authenticatedOuterEventIdentity:
                        Array(communicationKey.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        recipientEventIdentity,
                    authenticatedMessageIdentifier: try .init(
                        bytes: MosaicUnsignedTransactionTranscriptFixtures
                            .indexedDigest(30_000 + index)
                    ),
                    currentUnixSeconds: 1_800_000_000
                ),
                using: AcceptingAnonymousComponentValidator()
            )
            #expect(effects.count == 1)
            guard case .anonymousComponentAdmitted = effects[0] else {
                Issue.record("Expected an authorized anonymous component")
                return
            }
        }

        let componentRun = try Fixture.aggregateRun(
            canonicalBytes: prepared.preparation.componentSet.canonicalBytes,
            kind: .componentSet,
            sender: harness.election.result.roster.conductor,
            phase: .anonymousComponentSubmission,
            sequence: commitmentRun.nextSequence,
            harness: harness
        )
        let componentEffects = Fixture.admit(componentRun, to: &harness.ledger)
        let transcript = try #require(
            componentEffects.compactMap { effect -> Ledger.Transcript? in
                guard case let .componentSetAdmitted(_, transcript) = effect else {
                    return nil
                }
                return transcript
            }.first
        )
        #expect(
            try synchronize(
                &harness.ledger,
                to: .transcriptAgreement(transcript)
            ) == [.phaseAdvanced(.transcriptAgreement(transcript))]
        )

        let acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: harness.election.result.roster.contributors,
                binding: harness.manifest.binding,
                transcriptRoot: transcript.transcriptRoot,
                profile: .opalMainnetAlpha
            )
        var wrongRootLedger = harness.ledger
        let firstAcknowledgement = try #require(acknowledgements.first)
        let wrongRoot = try OpalFusion.Mosaic.Attempt.TranscriptRoot(
            validating: [UInt8](repeating: 0xD1, count: 32)
        )
        let wrongAcknowledgement = try #require(
            MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                for: [firstAcknowledgement.contributor],
                binding: harness.manifest.binding,
                transcriptRoot: wrongRoot,
                profile: .opalMainnetAlpha
            ).first
        )
        #expect(
            wrongRootLedger.apply(
                input: .control(
                    try acknowledgementDelivery(
                        wrongAcknowledgement,
                        sequence: try #require(
                            prepared.nextContributorSequenceByIdentity[
                                wrongAcknowledgement.contributor
                            ]
                        ),
                        harness: harness
                    )
                )
            ) == [
                .attemptTerminated(
                    .failed(.transcriptAcknowledgementMismatch)
                )
            ]
        )

        let acknowledgementDeliveries = try acknowledgements.reversed().map {
            acknowledgement in
            let sequence = try #require(
                prepared.nextContributorSequenceByIdentity[
                    acknowledgement.contributor
                ]
            )
            return try acknowledgementDelivery(
                acknowledgement,
                sequence: sequence,
                harness: harness
            )
        }
        for delivery in acknowledgementDeliveries.dropLast() {
            let effects = harness.ledger.apply(input: .control(delivery))
            #expect(
                !effects.contains { effect in
                    if case .preSignAcknowledgementCollectionComplete = effect {
                        true
                    } else {
                        false
                    }
                }
            )
        }
        let finalDelivery = try #require(acknowledgementDeliveries.last)
        let finalEffects = harness.ledger.apply(input: .control(finalDelivery))
        let collection = finalEffects.compactMap {
            effect -> [Alpha.PreSignAcknowledgementSubmission]? in
            guard case let .preSignAcknowledgementCollectionComplete(values)
                = effect else {
                return nil
            }
            return values
        }.first
        #expect(
            harness.ledger.apply(input: .control(finalDelivery))
                == [.exactDuplicateIgnored]
        )
        let collectedAcknowledgements = try #require(collection)
        let expectedContributors = harness.election.result.roster.contributors
            .sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
        #expect(
            collectedAcknowledgements.map(\.acknowledgement.contributor)
                == expectedContributors
        )
        var conflictingAcknowledgementLedger = harness.ledger
        let repeatedAcknowledgement = try #require(acknowledgements.first)
        #expect(
            conflictingAcknowledgementLedger.apply(
                input: .control(
                    try acknowledgementDelivery(
                        repeatedAcknowledgement,
                        sequence: finalDelivery.envelope.sequence + 1,
                        harness: harness
                    )
                )
            ) == [
                .attemptTerminated(
                    .failed(
                        .conflictingDocument(
                            .preSignAcknowledgement(
                                repeatedAcknowledgement.contributor
                            )
                        )
                    )
                )
            ]
        )
        #expect(
            try synchronize(&harness.ledger, to: .bchSigning(transcript))
                == [
                    .attemptTerminated(.failed(.bchSigningAdmissionUnavailable))
                ]
        )
    }

    private struct PreparedTranscript {
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        let nextConductorSequence: UInt64
    }

    private struct RejectingAnonymousComponentValidator:
        Alpha.AnonymousComponentAdmissionValidating
    {
        struct Rejection: Error {}

        func validateComponentAdmission(
            senderCommunicationPublicKey: [UInt8],
            payload: OpalFusion.Mosaic.OpalV0.AnonymousComponentPayload
        ) throws {
            throw Rejection()
        }
    }

    private struct AcceptingAnonymousComponentValidator:
        Alpha.AnonymousComponentAdmissionValidating
    {
        func validateComponentAdmission(
            senderCommunicationPublicKey _: [UInt8],
            payload _: OpalFusion.Mosaic.OpalV0.AnonymousComponentPayload
        ) throws {}
    }

    private struct AcceptingPhaseTransitionValidator:
        Ledger.PhaseTransitionValidating
    {
        func validatePhaseTransition(
            _: Ledger.PhaseTransitionRequest
        ) throws {}
    }

    private struct RejectingPhaseTransitionValidator:
        Ledger.PhaseTransitionValidating
    {
        struct Rejection: Error {}

        func validatePhaseTransition(
            _: Ledger.PhaseTransitionRequest
        ) throws {
            throw Rejection()
        }
    }

    private struct PreparedConductorCommitments {
        let preparation: MosaicUnsignedTransactionTranscriptFixtures.Prepared
        let nextConductorSequence: UInt64
        let nextContributorSequenceByIdentity: [Ledger.ControlIdentity: UInt64]
    }

    private func synchronize(
        _ ledger: inout Ledger,
        to nextContext: Ledger.PhaseContext
    ) throws -> [Ledger.Effect] {
        let request = try #require(
            ledger.phaseTransitionRequest(to: nextContext)
        )
        return ledger.synchronize(
            using: try transitionValidation(request)
        )
    }

    private func transitionValidation(
        _ request: Ledger.PhaseTransitionRequest
    ) throws -> Ledger.PhaseTransitionValidation {
        try Ledger.PhaseTransitionValidation(
            validating: request,
            using: AcceptingPhaseTransitionValidator()
        )
    }

    private func acknowledgementDelivery(
        _ acknowledgement: OpalFusion.Mosaic.Attempt.TranscriptAcknowledgement,
        sequence: UInt64,
        harness: Fixture.Harness
    ) throws -> Ledger.ControlDelivery {
        let envelope = try Fixture.signedEnvelope(
            sender: acknowledgement.contributor,
            phase: .transcriptAgreement,
            payloadType: .preSignAcknowledgement,
            payload: try Alpha.CanonicalWireCodec
                .encodePreSignAcknowledgementSubmission(
                    roundIdentifier: acknowledgement.roundIdentifier,
                    transcriptRoot: acknowledgement.transcriptRoot,
                    signature: acknowledgement.rawRepresentation
                ),
            sequence: sequence,
            roundIdentifier: harness.manifest.core.roundIdentifier
        )
        return Fixture.controlDelivery(envelope: envelope, harness: harness)
    }

    private func manifestRun(
        harness: Fixture.Harness
    ) throws -> Fixture.AggregateRun {
        try Fixture.aggregateRun(
            canonicalBytes: harness.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: harness
        )
    }

    @discardableResult
    private func admitManifestAndAdvanceWallet(
        harness: inout Fixture.Harness
    ) throws -> UInt64 {
        let run = try manifestRun(harness: harness)
        let effects = Fixture.admit(run, to: &harness.ledger)
        try #require(effects.contains(.manifestAdmitted(harness.manifest)))
        let walletEffects = try synchronize(
            &harness.ledger,
            to: .walletReservation
        )
        try #require(walletEffects == [.phaseAdvanced(.walletReservation)])
        return run.nextSequence
    }

    private func prepareTranscript(
        harness: inout Fixture.Harness
    ) throws -> PreparedTranscript {
        var conductorSequence = try admitManifestAndAdvanceWallet(
            harness: &harness
        )
        let groupedCommitmentEffects = try synchronize(
            &harness.ledger,
            to: .groupedCommitment
        )
        try #require(
            groupedCommitmentEffects == [.phaseAdvanced(.groupedCommitment)]
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.election.result.roster,
            manifest: harness.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let commitmentRun = try Fixture.aggregateRun(
            canonicalBytes: preparation.commitmentSet.canonicalBytes,
            kind: .commitmentSet,
            sender: harness.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: conductorSequence,
            harness: harness
        )
        let commitmentEffects = Fixture.admit(
            commitmentRun,
            to: &harness.ledger
        )
        try #require(
            commitmentEffects.contains(
                .commitmentSetAdmitted(preparation.commitmentSet)
            )
        )
        conductorSequence = commitmentRun.nextSequence
        let anonymousComponentEffects = try synchronize(
            &harness.ledger,
            to: .anonymousComponentSubmission
        )
        try #require(
            anonymousComponentEffects
                == [.phaseAdvanced(.anonymousComponentSubmission)]
        )
        let componentRun = try Fixture.aggregateRun(
            canonicalBytes: preparation.componentSet.canonicalBytes,
            kind: .componentSet,
            sender: harness.election.result.roster.conductor,
            phase: .anonymousComponentSubmission,
            sequence: conductorSequence,
            harness: harness
        )
        let componentEffects = Fixture.admit(componentRun, to: &harness.ledger)
        let transcript = try #require(
            componentEffects.compactMap { effect -> Ledger.Transcript? in
                guard case let .componentSetAdmitted(_, transcript) = effect else {
                    return nil
                }
                return transcript
            }.first
        )
        return .init(
            transcript: transcript,
            nextConductorSequence: componentRun.nextSequence
        )
    }

    private func prepareConductorCommitments(
        harness: inout Fixture.Harness
    ) throws -> PreparedConductorCommitments {
        let conductorSequence = try admitManifestAndAdvanceWallet(
            harness: &harness
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.election.result.roster,
            manifest: harness.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let commits = try Fixture.makePlayerCommits(
            harness: harness,
            commitmentSet: preparation.commitmentSet
        )
        var reachedUnanimity = false
        var nextContributorSequenceByIdentity: [
            Ledger.ControlIdentity: UInt64
        ] = [:]
        for commit in commits {
            let run = try Fixture.aggregateRun(
                canonicalBytes: commit.canonicalBytes,
                kind: .playerCommit,
                sender: commit.contributor,
                phase: .walletReservation,
                sequence: 0,
                harness: harness
            )
            reachedUnanimity = Fixture.admit(run, to: &harness.ledger).contains {
                if case .playerCommitUnanimityReached = $0 {
                    true
                } else {
                    false
                }
            } || reachedUnanimity
            nextContributorSequenceByIdentity[commit.contributor]
                = run.nextSequence
        }
        try #require(reachedUnanimity)
        let groupedCommitmentEffects = try synchronize(
            &harness.ledger,
            to: .groupedCommitment
        )
        try #require(
            groupedCommitmentEffects == [.phaseAdvanced(.groupedCommitment)]
        )
        return .init(
            preparation: preparation,
            nextConductorSequence: conductorSequence,
            nextContributorSequenceByIdentity:
                nextContributorSequenceByIdentity
        )
    }

}
