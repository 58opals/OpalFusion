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

    @Test("Derive a zero sequence epoch and require a local roster member")
    func validateInitialization() throws {
        let conductorHarness = try Fixture.makeHarness(localRole: .conductor)
        #expect(conductorHarness.ledger.state == .active(.manifestAgreement))
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
                materialIdentifier: conductorHarness.materialIdentifier,
                localControlIdentity: unknownIdentity,
                proposalValidation: conductorHarness.proposalValidation
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
            verificationKey: harness.manifest.core
                .componentAuthorizationVerificationKey,
            bchSignatureVerificationKey: harness.manifest.core
                .bchSignatureAuthorizationVerificationKey,
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

    @Test("Enforce strict replay, conflict, gap, and a fresh-round zero epoch")
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

        var freshRoundHarness = try Fixture.makeHarness(localRole: .contributor)
        let freshRoundRun = try manifestRun(harness: freshRoundHarness)
        #expect(
            freshRoundHarness.ledger.apply(
                input: .control(freshRoundRun.reservation)
            ).count == 1
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

    @Test("Reject PlayerCommit fee-share and Pedersen-balance violations")
    func rejectInvalidPlayerCommitSemantics() throws {
        var wrongShareHarness = try Fixture.makeHarness(localRole: .conductor)
        _ = try admitManifestAndAdvanceWallet(harness: &wrongShareHarness)
        let contributors = wrongShareHarness.election.result.roster.contributors
            .sorted {
                $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
            }
        let commitmentGroups = try MosaicUnsignedTransactionTranscriptFixtures
            .makeMainnetCommitmentGroups(contributorCount: contributors.count)
        let wrongShareGroup = commitmentGroups[4]
        let wrongShareCommit = try Alpha.PlayerCommit(
            roundIdentifier: wrongShareHarness.manifest.core.roundIdentifier,
            contributor: contributors[0],
            groupedCommitment: try .init(
                profile: .opalMainnetAlpha,
                commitments: wrongShareGroup.commitments,
                excessFeeSatoshis: wrongShareGroup.excessFeeSatoshis,
                pedersenTotalNonce: wrongShareGroup.pedersenTotalNonce
            ),
            componentAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(),
            bchSignatureAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(byteOffset: 0x40)
        )
        let wrongShareRun = try Fixture.aggregateRun(
            canonicalBytes: wrongShareCommit.canonicalBytes,
            kind: .playerCommit,
            sender: wrongShareCommit.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: wrongShareHarness
        )
        let wrongShareEffects = Fixture.admit(
            wrongShareRun,
            to: &wrongShareHarness.ledger
        )
        #expect(
            wrongShareEffects.last == .attemptTerminated(
                .failed(
                    .playerCommitSemanticValidationFailed(
                        .excessFeeMismatch(expected: 2, actual: 1)
                    )
                )
            )
        )
        #expect(!wrongShareEffects.contains(.playerCommitAdmitted(wrongShareCommit)))

        var wrongBalanceHarness = try Fixture.makeHarness(localRole: .conductor)
        _ = try admitManifestAndAdvanceWallet(harness: &wrongBalanceHarness)
        let exactGroup = commitmentGroups[0]
        let wrongBalanceCommit = try Alpha.PlayerCommit(
            roundIdentifier: wrongBalanceHarness.manifest.core.roundIdentifier,
            contributor: contributors[0],
            groupedCommitment: try .init(
                profile: .opalMainnetAlpha,
                commitments: exactGroup.commitments,
                excessFeeSatoshis: exactGroup.excessFeeSatoshis,
                pedersenTotalNonce: [UInt8](repeating: 0, count: 31) + [0x7F]
            ),
            componentAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(),
            bchSignatureAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(byteOffset: 0x40)
        )
        let wrongBalanceRun = try Fixture.aggregateRun(
            canonicalBytes: wrongBalanceCommit.canonicalBytes,
            kind: .playerCommit,
            sender: wrongBalanceCommit.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: wrongBalanceHarness
        )
        let wrongBalanceEffects = Fixture.admit(
            wrongBalanceRun,
            to: &wrongBalanceHarness.ledger
        )
        #expect(
            wrongBalanceEffects.last == .attemptTerminated(
                .failed(
                    .playerCommitSemanticValidationFailed(
                        .pedersenBalanceMismatch
                    )
                )
            )
        )
        #expect(
            !wrongBalanceEffects.contains(
                .playerCommitAdmitted(wrongBalanceCommit)
            )
        )

        var parityHarness = try Fixture.makeHarness(localRole: .conductor)
        _ = try admitManifestAndAdvanceWallet(harness: &parityHarness)
        let validCommit = try Alpha.PlayerCommit(
            roundIdentifier: parityHarness.manifest.core.roundIdentifier,
            contributor: contributors[0],
            groupedCommitment: try .init(
                profile: .opalMainnetAlpha,
                commitments: commitmentGroups[0].commitments,
                excessFeeSatoshis: commitmentGroups[0].excessFeeSatoshis,
                pedersenTotalNonce: commitmentGroups[0].pedersenTotalNonce
            ),
            componentAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(),
            bchSignatureAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(byteOffset: 0x40)
        )
        var parityBytes = validCommit.canonicalBytes
        let firstCommunicationKeyOffset = 32 + 32 + 4 + 32 + 65
        let secondCommunicationKeyOffset = firstCommunicationKeyOffset + 130
        var oppositeParityKey = Array(
            parityBytes[
                firstCommunicationKeyOffset ..< firstCommunicationKeyOffset + 33
            ]
        )
        oppositeParityKey[0] = oppositeParityKey[0] == 0x02 ? 0x03 : 0x02
        parityBytes.replaceSubrange(
            secondCommunicationKeyOffset ..< secondCommunicationKeyOffset + 33,
            with: oppositeParityKey
        )
        let parityRun = try Fixture.aggregateRun(
            canonicalBytes: parityBytes,
            kind: .playerCommit,
            sender: validCommit.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: parityHarness
        )
        #expect(
            Fixture.admit(parityRun, to: &parityHarness.ledger).last
                == .attemptTerminated(
                    .failed(
                        .aggregateReassemblyFailed(
                            .invalidCanonicalAggregate(.playerCommit)
                        )
                    )
                )
        )
    }

    @Test(
        "Require one response set for every contributor",
        arguments: [7, 8, 9]
    )
    func requireAuthorizationResponseSets(candidateCount: Int) throws {
        var harness = try Fixture.makeHarness(
            candidateCount: candidateCount,
            localRole: .conductor
        )
        var conductorSequence = try admitManifestAndAdvanceWallet(
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
        for commit in commits {
            let run = try Fixture.aggregateRun(
                canonicalBytes: commit.canonicalBytes,
                kind: .playerCommit,
                sender: commit.contributor,
                phase: .walletReservation,
                sequence: 0,
                harness: harness
            )
            _ = Fixture.admit(run, to: &harness.ledger)
        }
        let responseSets = try commits.enumerated().map { index, commit in
            try Fixture.makeAuthorizationResponseSet(
                playerCommit: commit,
                byteSeed: UInt8(index + 1)
            )
        }
        for responseSet in responseSets.dropLast() {
            let run = try Fixture.aggregateRun(
                canonicalBytes: responseSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: harness.election.result.roster.conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                harness: harness
            )
            _ = Fixture.admit(run, to: &harness.ledger)
            conductorSequence = run.nextSequence
        }
        var incompleteLedger = harness.ledger
        #expect(
            try synchronize(&incompleteLedger, to: .groupedCommitment)
                == [
                    .attemptTerminated(
                        .failed(
                            .phaseAdvancePrerequisiteMissing(
                                .groupedCommitment
                            )
                        )
                    )
                ]
        )
        let finalSet = try #require(responseSets.last)
        let finalRun = try Fixture.aggregateRun(
            canonicalBytes: finalSet.canonicalBytes,
            kind: .authorizationResponseSet,
            sender: harness.election.result.roster.conductor,
            phase: .walletReservation,
            sequence: conductorSequence,
            harness: harness
        )
        #expect(
            Fixture.admit(finalRun, to: &harness.ledger)
                .contains(.authorizationResponseSetAdmitted(finalSet))
        )
        #expect(
            try synchronize(&harness.ledger, to: .groupedCommitment)
                == [.phaseAdvanced(.groupedCommitment)]
        )
    }

    @Test("Consume one conductor response stream and bind the local set")
    func bindAuthorizationResponseSet() throws {
        var contributorHarness = try Fixture.makeHarness(
            localRole: .contributor,
            localContributorIndex: 2
        )
        var conductorSequence = try admitManifestAndAdvanceWallet(
            harness: &contributorHarness
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: contributorHarness.election.result.roster,
            manifest: contributorHarness.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let commits = try Fixture.makePlayerCommits(
            harness: contributorHarness,
            commitmentSet: preparation.commitmentSet
        )
        let localCommit = try #require(
            commits.first {
                $0.contributor == contributorHarness.localControlIdentity
            }
        )
        let localCommitRun = try Fixture.aggregateRun(
            canonicalBytes: localCommit.canonicalBytes,
            kind: .playerCommit,
            sender: localCommit.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: contributorHarness
        )
        _ = Fixture.admit(localCommitRun, to: &contributorHarness.ledger)

        for commit in commits {
            let responseSet = try Fixture.makeAuthorizationResponseSet(
                playerCommit: commit
            )
            let run = try Fixture.aggregateRun(
                canonicalBytes: responseSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: contributorHarness.election.result.roster.conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                harness: contributorHarness
            )
            let effects = Fixture.admit(run, to: &contributorHarness.ledger)
            #expect(
                effects.contains(.authorizationResponseSetAdmitted(responseSet))
            )
            if commit.contributor == contributorHarness.localControlIdentity {
                #expect(
                    effects.contains(
                        .authorizationResponseSetValidationRequired(
                            responseSet,
                            playerCommit: localCommit
                        )
                    )
                )
            } else {
                #expect(
                    !effects.contains {
                        if case .authorizationResponseSetValidationRequired = $0 {
                            true
                        } else {
                            false
                        }
                    }
                )
            }
            conductorSequence = run.nextSequence
        }
        #expect(
            try synchronize(
                &contributorHarness.ledger,
                to: .groupedCommitment
            ) == [
                .attemptTerminated(
                    .failed(
                        .phaseAdvancePrerequisiteMissing(.groupedCommitment)
                    )
                )
            ]
        )

        var conductorHarness = try Fixture.makeHarness(localRole: .conductor)
        let nextConductorSequence = try admitManifestAndAdvanceWallet(
            harness: &conductorHarness
        )
        let conductorPreparation = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: conductorHarness.election.result.roster,
                manifest: conductorHarness.manifest.binding,
                profile: .opalMainnetAlpha
            )
        let playerCommit = try Fixture.makePlayerCommits(
            harness: conductorHarness,
            commitmentSet: conductorPreparation.commitmentSet
        )[0]
        let playerRun = try Fixture.aggregateRun(
            canonicalBytes: playerCommit.canonicalBytes,
            kind: .playerCommit,
            sender: playerCommit.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: conductorHarness
        )
        _ = Fixture.admit(playerRun, to: &conductorHarness.ledger)
        var wrongDigest = playerCommit.digest
        wrongDigest[0] ^= 0x01
        let wrongSet = try Alpha.AuthorizationResponseSet(
            roundIdentifier: playerCommit.roundIdentifier,
            contributor: playerCommit.contributor,
            playerCommitDigest: wrongDigest,
            componentAuthorizationResponses: try Fixture
                .makeAuthorizationResponseSet(playerCommit: playerCommit)
                .componentAuthorizationResponses,
            bchSignatureAuthorizationResponses: try Fixture
                .makeAuthorizationResponseSet(playerCommit: playerCommit)
                .bchSignatureAuthorizationResponses
        )
        let wrongRun = try Fixture.aggregateRun(
            canonicalBytes: wrongSet.canonicalBytes,
            kind: .authorizationResponseSet,
            sender: conductorHarness.election.result.roster.conductor,
            phase: .walletReservation,
            sequence: nextConductorSequence,
            harness: conductorHarness
        )
        #expect(
            Fixture.admit(wrongRun, to: &conductorHarness.ledger).last
                == .attemptTerminated(
                    .failed(.authorizationResponseSetPlayerCommitMismatch)
                )
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

    @Test("Admit the portable acknowledgement set before contributor BCH signing")
    func advanceContributorAfterPortableAcknowledgements() throws {
        let evaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let verificationKey = try #require(evaluator.verificationKey)
        var harness = try Fixture.makeHarness(
            localRole: .contributor,
            localContributorIndex: 2,
            verificationKey: verificationKey
        )
        let prepared = try prepareTranscript(
            harness: &harness,
            evaluator: evaluator
        )
        #expect(
            try synchronize(
                &harness.ledger,
                to: .transcriptAgreement(prepared.transcript)
            ) == [.phaseAdvanced(.transcriptAgreement(prepared.transcript))]
        )

        let contributor = harness.localControlIdentity
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
            sequence: prepared.nextContributorSequence,
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
        let completeAcknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: harness.election.result.roster.contributors,
                binding: harness.manifest.binding,
                transcriptRoot: prepared.transcript.transcriptRoot,
                profile: .opalMainnetAlpha
            )
            .sorted {
                $0.contributor.validatedBytes.lexicographicallyPrecedes(
                    $1.contributor.validatedBytes
                )
            }
        let submissions = try completeAcknowledgements.map {
            try Alpha.PreSignAcknowledgementSubmission(
                contributor: $0.contributor,
                roundIdentifier: $0.roundIdentifier,
                transcriptRoot: $0.transcriptRoot,
                signature: $0.rawRepresentation
            )
        }
        let acknowledgementSet = try Alpha.PreSignAcknowledgementSet(
            roundIdentifier: harness.manifest.core.roundIdentifier,
            transcriptRoot: prepared.transcript.transcriptRoot.validatedBytes,
            roster: harness.election.result.roster,
            submissions: submissions
        )
        let acknowledgementSetRun = try Fixture.aggregateRun(
            canonicalBytes: acknowledgementSet.canonicalBytes,
            kind: .preSignAcknowledgementSet,
            sender: harness.election.result.roster.conductor,
            phase: .transcriptAgreement,
            sequence: prepared.nextConductorSequence,
            harness: harness
        )
        #expect(
            Fixture.admit(acknowledgementSetRun, to: &harness.ledger)
                .contains(.preSignAcknowledgementSetAdmitted(acknowledgementSet))
        )
        #expect(
            try synchronize(
                &harness.ledger,
                to: .bchSigning(prepared.transcript)
            ) == [
                .phaseAdvanced(.bchSigning(prepared.transcript))
            ]
        )
    }

    @Test("Reject BCH payloads at the component boundary and absorb terminal input")
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
                anonymousDelivery
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
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xA4, count: 32)
            ),
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
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
        let evaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
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

        let firstComponent = prepared.preparation.componentSet.components[0]
        let authorizationInput = try Alpha.AuthorizationTokenInput(
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                keyIdentifier: [UInt8](verificationKey.keyIdentifier),
                purpose: .component,
                nonce: [UInt8](repeating: 0x91, count: 32),
                binding: try Alpha.AuthorizationTokenInput.componentBinding(
                    for: firstComponent
                )
        )
        let authorizationRequest = try Alpha.AuthorizationRequest(
            input: authorizationInput,
            using: verificationKey
        )
        let authorizationToken = try authorizationRequest.finalize(
            evaluator.evaluate(authorizationRequest.blindedMessage)
        )
        let componentPayload = try Alpha.AnonymousComponentPayload(
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                authorizationToken: authorizationToken,
                component: firstComponent
        )
        var publishedKeyReuseLedger = conductorHarness.ledger
        var publishedKeyOppositeParityLedger = conductorHarness.ledger
        let publishedCommunicationKey = prepared.preparation.commitmentSet
            .commitments[0].communicationPublicKey
        let publishedKeyEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: publishedCommunicationKey,
            recipientEventIdentity: Fixture.eventIdentity(scalarByte: 251),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_060,
            payload: try Alpha.CanonicalWireCodec
                .encodeAnonymousComponent(componentPayload)
        )
        #expect(
            publishedKeyReuseLedger.receiveAnonymousComponent(
                .init(
                    attemptIdentifier: conductorHarness.attemptIdentifier,
                    generationIdentifier: conductorHarness.generationIdentifier,
                    envelope: publishedKeyEnvelope,
                    authenticatedOuterEventIdentity:
                        Array(publishedCommunicationKey.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        publishedKeyEnvelope.recipientEventIdentity,
                    authenticatedMessageIdentifier: try .init(
                        bytes: [UInt8](repeating: 0xE1, count: 32)
                    ),
                    currentUnixSeconds: 1_800_000_000
                )
            ) == [
                .attemptTerminated(.failed(.anonymousCommunicationKeyReuse))
            ]
        )
        var publishedKeyOppositeParity = publishedCommunicationKey
        publishedKeyOppositeParity[0] = publishedCommunicationKey[0] == 0x02
            ? 0x03
            : 0x02
        let publishedKeyOppositeParityEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: publishedKeyOppositeParity,
            recipientEventIdentity: Fixture.eventIdentity(scalarByte: 247),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_060,
            payload: try Alpha.CanonicalWireCodec
                .encodeAnonymousComponent(componentPayload)
        )
        #expect(
            publishedKeyOppositeParityLedger.receiveAnonymousComponent(
                .init(
                    attemptIdentifier: conductorHarness.attemptIdentifier,
                    generationIdentifier: conductorHarness.generationIdentifier,
                    envelope: publishedKeyOppositeParityEnvelope,
                    authenticatedOuterEventIdentity:
                        Array(publishedKeyOppositeParity.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        publishedKeyOppositeParityEnvelope.recipientEventIdentity,
                    authenticatedMessageIdentifier: try .init(
                        bytes: [UInt8](repeating: 0xE0, count: 32)
                    ),
                    currentUnixSeconds: 1_800_000_000
                )
            ) == [
                .attemptTerminated(.failed(.anonymousCommunicationKeyReuse))
            ]
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
            payload: try Alpha.CanonicalWireCodec
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
        var oppositeParityCommunicationKeyReuseLedger = conductorHarness.ledger
        let accepted = conductorHarness.ledger.receiveAnonymousComponent(
            delivery
        )
        _ = messageConflictLedger.receiveAnonymousComponent(
            delivery
        )
        _ = recipientReuseLedger.receiveAnonymousComponent(
            delivery
        )
        _ = communicationKeyReuseLedger.receiveAnonymousComponent(
            delivery
        )
        _ = oppositeParityCommunicationKeyReuseLedger
            .receiveAnonymousComponent(delivery)
        #expect(accepted.count == 1)
        guard case .anonymousComponentAdmitted = accepted[0] else {
            Issue.record("Expected one admitted anonymous component")
            return
        }
        #expect(
            conductorHarness.ledger.receiveAnonymousComponent(
                delivery
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
            payload: try Alpha.CanonicalWireCodec
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
                )
            ) == [.attemptTerminated(.failed(.anonymousMessageConflict))]
        )

        let secondComponent = prepared.preparation.componentSet.components[1]
        let secondAuthorizationInput = try Alpha.AuthorizationTokenInput(
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                keyIdentifier: [UInt8](verificationKey.keyIdentifier),
                purpose: .component,
                nonce: [UInt8](repeating: 0x92, count: 32),
                binding: try Alpha.AuthorizationTokenInput.componentBinding(
                    for: secondComponent
                )
        )
        let secondAuthorizationRequest = try Alpha.AuthorizationRequest(
            input: secondAuthorizationInput,
            using: verificationKey
        )
        let secondToken = try secondAuthorizationRequest.finalize(
            evaluator.evaluate(secondAuthorizationRequest.blindedMessage)
        )
        let secondPayload = try Alpha.AnonymousComponentPayload(
                roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
                authorizationToken: secondToken,
                component: secondComponent
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
            payload: try Alpha.CanonicalWireCodec
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
                )
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
            payload: try Alpha.CanonicalWireCodec
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
                )
            ) == [
                .attemptTerminated(.failed(.anonymousCommunicationKeyReuse))
            ]
        )
        var oppositeParityCommunicationKey = communicationKey
        oppositeParityCommunicationKey[0] = communicationKey[0] == 0x02
            ? 0x03
            : 0x02
        let oppositeParityCommunicationKeyEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: conductorHarness.manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: oppositeParityCommunicationKey,
            recipientEventIdentity: Fixture.eventIdentity(scalarByte: 248),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_060,
            payload: try Alpha.CanonicalWireCodec
                .encodeAnonymousComponent(secondPayload)
        )
        #expect(
            oppositeParityCommunicationKeyReuseLedger
                .receiveAnonymousComponent(
                    .init(
                        attemptIdentifier:
                            conductorHarness.attemptIdentifier,
                        generationIdentifier:
                            conductorHarness.generationIdentifier,
                        envelope: oppositeParityCommunicationKeyEnvelope,
                        authenticatedOuterEventIdentity:
                            Array(oppositeParityCommunicationKey.dropFirst()),
                        authenticatedRecipientEventIdentity:
                            oppositeParityCommunicationKeyEnvelope
                                .recipientEventIdentity,
                        authenticatedMessageIdentifier: try .init(
                            bytes: [UInt8](repeating: 0xE6, count: 32)
                        ),
                        currentUnixSeconds: 1_800_000_000
                    )
                ) == [
                    .attemptTerminated(
                        .failed(.anonymousCommunicationKeyReuse)
                    )
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
                conflictingDelivery
            ) == [
                .attemptTerminated(.failed(.anonymousAuthorizationConflict))
            ]
        )
        #expect(
            conductorHarness.ledger.receiveAnonymousComponent(
                delivery
            ) == [.exactDuplicateIgnored]
        )

        var contributorHarness = try Fixture.makeHarness(
            localRole: .contributor,
            verificationKey: verificationKey
        )
        _ = try prepareTranscript(
            harness: &contributorHarness,
            evaluator: evaluator
        )
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
                )
            ) == [.inputRejected(.anonymousComponentAdmissionUnavailable)]
        )
    }

    @Test(
        "Collect conductor acknowledgements and admit every anonymous BCH signature",
        .timeLimit(.minutes(5))
    )
    func collectConductorAcknowledgementsAndSignatures() throws {
        let evaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let verificationKey = try #require(evaluator.verificationKey)
        var harness = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: verificationKey
        )
        let prepared = try prepareConductorCommitments(
            harness: &harness,
            materialized: true
        )
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

        var acceptedComponentValidations: [
            Alpha.AnonymousComponentAdmissionValidation
        ] = []
        let authorizationMaterial = try #require(
            prepared.authorizationMaterial
        )
        for (index, component) in prepared.preparation.componentSet.components
            .enumerated() {
            let token: Alpha.AuthorizationToken
            if let materialSlot = authorizationMaterial.material.slots
                .firstIndex(where: { $0.component == component }) {
                token = authorizationMaterial.validation
                    .componentAuthorizationTokens[materialSlot]
            } else {
                let authorizationInput = try Alpha.AuthorizationTokenInput(
                    roundIdentifier: harness.manifest.core.roundIdentifier,
                    keyIdentifier: [UInt8](verificationKey.keyIdentifier),
                    purpose: .component,
                    nonce: MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(20_000 + index),
                    binding: try Alpha.AuthorizationTokenInput.componentBinding(
                        for: component
                    )
                )
                let request = try Alpha.AuthorizationRequest(
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
                token = try request.finalize(blindSignature)
            }
            let payload = try Alpha.AnonymousComponentPayload(
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
                payload: try Alpha.CanonicalWireCodec
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
                )
            )
            #expect(effects.count == 1)
            guard case let .anonymousComponentAdmitted(validation) = effects[0]
            else {
                Issue.record("Expected an authorized anonymous component")
                return
            }
            acceptedComponentValidations.append(validation)
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
        let portableSubmissions = try acknowledgements.sorted {
            $0.contributor.validatedBytes.lexicographicallyPrecedes(
                $1.contributor.validatedBytes
            )
        }.map {
            try Alpha.PreSignAcknowledgementSubmission(
                contributor: $0.contributor,
                roundIdentifier: $0.roundIdentifier,
                transcriptRoot: $0.transcriptRoot,
                signature: $0.rawRepresentation
            )
        }
        let portableAcknowledgementSet = try Alpha.PreSignAcknowledgementSet(
            roundIdentifier: harness.manifest.core.roundIdentifier,
            transcriptRoot: transcript.transcriptRoot.validatedBytes,
            roster: harness.election.result.roster,
            submissions: portableSubmissions
        )
        let portableRun = try Fixture.aggregateRun(
            canonicalBytes: portableAcknowledgementSet.canonicalBytes,
            kind: .preSignAcknowledgementSet,
            sender: harness.election.result.roster.conductor,
            phase: .transcriptAgreement,
            sequence: componentRun.nextSequence,
            harness: harness
        )
        var earlyPublicationLedger = harness.ledger
        #expect(
            Fixture.admit(portableRun, to: &earlyPublicationLedger).last
                == .attemptTerminated(
                    .failed(
                        .preSignAcknowledgementSetDoesNotMatchCollection
                    )
                )
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
        #expect(collectedAcknowledgements == portableSubmissions)
        #expect(
            Fixture.admit(portableRun, to: &harness.ledger)
                .contains(
                    .preSignAcknowledgementSetAdmitted(
                        portableAcknowledgementSet
                    )
                )
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
        var foreignTranscriptLedger = harness.ledger
        let foreignTranscript = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: harness.election.result.roster,
                manifest: harness.manifest.binding,
                profile: .opalMainnetAlpha,
                componentSaltOffset: 1
            ).transcript
        #expect(
            try synchronize(
                &foreignTranscriptLedger,
                to: .bchSigning(foreignTranscript)
            ) == [
                .attemptTerminated(
                    .failed(.phaseAdvancePrerequisiteMissing(.bchSigning))
                )
            ]
        )
        #expect(
            try synchronize(&harness.ledger, to: .bchSigning(transcript))
                == [.phaseAdvanced(.bchSigning(transcript))]
        )

        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let bchVerificationKey = try #require(bchEvaluator.verificationKey)
        #expect(
            bchVerificationKey
                == harness.manifest.core
                    .bchSignatureAuthorizationVerificationKey
        )
        let acceptedInputs = acceptedComponentValidations.filter {
            if case .input = $0.payload.component.payload {
                true
            } else {
                false
            }
        }.sorted { lhs, rhs in
            guard case let .input(left) = lhs.payload.component.payload,
                  case let .input(right) = rhs.payload.component.payload else {
                return false
            }
            if left.previousTransactionHash != right.previousTransactionHash {
                return left.previousTransactionHash.lexicographicallyPrecedes(
                    right.previousTransactionHash
                )
            }
            return left.outputIndex < right.outputIndex
        }
        #expect(acceptedInputs.count == transcript.transaction.inputs.count)

        let materialInputSlot = try #require(
            authorizationMaterial.material.slots.firstIndex {
                if case .input = $0.component.payload {
                    true
                } else {
                    false
                }
            }
        )
        let materialInputComponent = authorizationMaterial.material
            .slots[materialInputSlot].component
        let materialInputIndex = try #require(
            acceptedInputs.firstIndex {
                $0.payload.component == materialInputComponent
            }
        )
        let materialAcceptedInput = acceptedInputs[materialInputIndex]

        let firstInput = try #require(acceptedInputs.first)
        let secondInput = try #require(acceptedInputs.dropFirst().first)
        let validFirstKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 4_000).compressed
        let validFirst = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: validFirstKey,
            nonceIndex: 40_000,
            messageIndex: 50_000,
            signatureScalar: 100
        )

        var componentToSignatureReuseLedger = harness.ledger
        var componentSenderOppositeParity =
            firstInput.senderCommunicationPublicKey
        componentSenderOppositeParity[0] =
            firstInput.senderCommunicationPublicKey[0] == 0x02 ? 0x03 : 0x02
        let componentToSignatureReuse = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: secondInput,
            inputIndex: 1,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: componentSenderOppositeParity,
            nonceIndex: 40_010,
            messageIndex: 50_010,
            signatureScalar: 109
        )
        #expect(
            componentToSignatureReuseLedger.receiveAnonymousBCHSignature(
                componentToSignatureReuse,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .attemptTerminated(.failed(.anonymousCommunicationKeyReuse))
            ]
        )

        let acceptedNonInput = try #require(
            acceptedComponentValidations.first {
                if case .input = $0.payload.component.payload {
                    false
                } else {
                    true
                }
            }
        )
        var componentMismatchLedger = harness.ledger
        let componentMismatch = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: acceptedNonInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 4_001).compressed,
            nonceIndex: 40_011,
            messageIndex: 50_011,
            signatureScalar: 110
        )
        #expect(
            componentMismatchLedger.receiveAnonymousBCHSignature(
                componentMismatch,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .inputRejected(
                    .anonymousBCHSignatureAdmissionRejected(
                        .anonymousBCHSignatureComponentMismatch
                    )
                )
            ]
        )
        #expect(
            componentMismatchLedger.receiveAnonymousBCHSignature(
                validFirst,
                using: AcceptingBCHSignatureValidator()
            ).contains { effect in
                if case .anonymousBCHSignatureAdmitted = effect {
                    true
                } else {
                    false
                }
            }
        )

        var materialTokenLedger = harness.ledger
        let materialTokenDelivery = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: materialAcceptedInput,
            inputIndex: UInt32(materialInputIndex),
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 3_999).compressed,
            nonceIndex: 39_999,
            messageIndex: 49_999,
            signatureScalar: 98,
            authorizationToken: authorizationMaterial.validation
                .bchSignatureAuthorizationTokens[materialInputSlot]
        )
        #expect(
            materialTokenLedger.receiveAnonymousBCHSignature(
                materialTokenDelivery,
                using: AcceptingBCHSignatureValidator()
            ).contains { effect in
                if case .anonymousBCHSignatureAdmitted = effect {
                    true
                } else {
                    false
                }
            }
        )

        var publishedSignatureKeyLedger = harness.ledger
        var publishedSignatureOppositeParityLedger = harness.ledger
        let publishedSignatureKey = prepared.preparation.commitmentSet
            .commitments[0].communicationPublicKey
        let publishedSignatureDelivery = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: publishedSignatureKey,
            nonceIndex: 40_099,
            messageIndex: 50_099,
            signatureScalar: 99
        )
        #expect(
            publishedSignatureKeyLedger.receiveAnonymousBCHSignature(
                publishedSignatureDelivery,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .attemptTerminated(.failed(.anonymousCommunicationKeyReuse))
            ]
        )
        var publishedSignatureOppositeParity = publishedSignatureKey
        publishedSignatureOppositeParity[0] = publishedSignatureKey[0] == 0x02
            ? 0x03
            : 0x02
        let publishedSignatureOppositeParityDelivery =
            try makeBCHSignatureDelivery(
                harness: harness,
                transcript: transcript,
                acceptedInput: firstInput,
                inputIndex: 0,
                authorizationEvaluator: bchEvaluator,
                authorizationVerificationKey: bchVerificationKey,
                communicationKey: publishedSignatureOppositeParity,
                nonceIndex: 40_098,
                messageIndex: 50_098,
                signatureScalar: 97
            )
        #expect(
            publishedSignatureOppositeParityLedger
                .receiveAnonymousBCHSignature(
                    publishedSignatureOppositeParityDelivery,
                    using: AcceptingBCHSignatureValidator()
                ) == [
                    .attemptTerminated(
                        .failed(.anonymousCommunicationKeyReuse)
                    )
                ]
        )

        var wrongSequenceLedger = harness.ledger
        let wrongSequence = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: validFirstKey,
            nonceIndex: 40_100,
            messageIndex: 50_100,
            signatureScalar: 101,
            sequence: 0
        )
        #expect(
            wrongSequenceLedger.receiveAnonymousBCHSignature(
                wrongSequence,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .inputRejected(
                    .anonymousMailboxSequenceInvalid(expected: 1, actual: 0)
                )
            ]
        )

        var missingComponentLedger = harness.ledger
        let unknownRecipient = [UInt8](
            try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: scalarBytes(9_000)
            ).bip340VerificationKey.rawRepresentation
        )
        let missingComponent = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: validFirstKey,
            nonceIndex: 40_101,
            messageIndex: 50_101,
            signatureScalar: 102,
            recipientEventIdentity: unknownRecipient
        )
        #expect(
            missingComponentLedger.receiveAnonymousBCHSignature(
                missingComponent,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .inputRejected(.anonymousBCHSignatureAdmissionUnavailable)
            ]
        )
        #expect(throws: Alpha.ContractError.invalidAuthorizationToken) {
            _ = try makeBCHSignatureDelivery(
                harness: harness,
                transcript: transcript,
                acceptedInput: firstInput,
                inputIndex: 0,
                authorizationEvaluator: bchEvaluator,
                authorizationVerificationKey: bchVerificationKey,
                communicationKey: validFirstKey,
                nonceIndex: 40_104,
                messageIndex: 50_104,
                signatureScalar: 105,
                authorizationPurpose: .component
            )
        }
        let validSubmission = try Alpha.CanonicalWireCodec
            .decodeBCHSignatureSubmission(from: validFirst.envelope.payload)
        let wrongPurposeInput = try Alpha.AuthorizationTokenInput(
            roundIdentifier: harness.manifest.core.roundIdentifier,
            keyIdentifier: [UInt8](verificationKey.keyIdentifier),
            purpose: .component,
            nonce: MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                40_102
            ),
            binding: firstInput.authorizationSpentIdentifier
        )
        let wrongPurposeRequest = try Alpha.AuthorizationRequest(
            input: wrongPurposeInput,
            using: verificationKey
        )
        let wrongPurposeToken = try wrongPurposeRequest.finalize(
            evaluator.evaluate(wrongPurposeRequest.blindedMessage)
        )
        let wrongPurposeKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 4_102).compressed
        let wrongPurposeEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: harness.manifest.core.roundIdentifier,
            phase: .bchSigning,
            senderCommunicationPublicKey: wrongPurposeKey,
            recipientEventIdentity: firstInput.recipientEventIdentity,
            sequence: 1,
            payloadType: .bchSignatureSubmission,
            expiryUnixSeconds: 1_800_000_060,
            payload: try Alpha.CanonicalWireCodec.encodeBCHSignatureSubmission(
                transcriptRoot: transcript.transcriptRoot.validatedBytes,
                authorizationToken: wrongPurposeToken,
                entry: validSubmission.entry
            )
        )
        var wrongPurposeLedger = harness.ledger
        #expect(
            wrongPurposeLedger.receiveAnonymousBCHSignature(
                .init(
                    attemptIdentifier: harness.attemptIdentifier,
                    generationIdentifier: harness.generationIdentifier,
                    envelope: wrongPurposeEnvelope,
                    authenticatedOuterEventIdentity:
                        Array(wrongPurposeKey.dropFirst()),
                    authenticatedRecipientEventIdentity:
                        firstInput.recipientEventIdentity,
                    authenticatedMessageIdentifier: try .init(
                        bytes: MosaicUnsignedTransactionTranscriptFixtures
                            .indexedDigest(50_102)
                    ),
                    currentUnixSeconds: 1_800_000_000
                ),
                using: AcceptingBCHSignatureValidator()
            ) == [
                .inputRejected(
                    .anonymousBCHSignatureAdmissionRejected(
                        .invalidAuthorizationToken
                    )
                )
            ]
        )

        let invalidDeliveries: [
            (Ledger.AnonymousComponentDelivery, Ledger.Failure)
        ] = [
            (
                try makeBCHSignatureDelivery(
                    harness: harness,
                    transcript: transcript,
                    acceptedInput: firstInput,
                    inputIndex: 0,
                    authorizationEvaluator: bchEvaluator,
                    authorizationVerificationKey: bchVerificationKey,
                    communicationKey: validFirstKey,
                    nonceIndex: 40_103,
                    messageIndex: 50_103,
                    signatureScalar: 104,
                    roundIdentifier: [UInt8](repeating: 0xF1, count: 32)
                ),
                .anonymousBCHSignatureAdmissionRejected(
                    .anonymousBCHSignatureRoundMismatch
                )
            ),
            (
                try makeBCHSignatureDelivery(
                    harness: harness,
                    transcript: transcript,
                    acceptedInput: firstInput,
                    inputIndex: 0,
                    authorizationEvaluator: evaluator,
                    authorizationVerificationKey: verificationKey,
                    communicationKey: validFirstKey,
                    nonceIndex: 40_105,
                    messageIndex: 50_105,
                    signatureScalar: 106
                ),
                .anonymousBCHSignatureAdmissionRejected(
                    .invalidAuthorizationToken
                )
            ),
            (
                try makeBCHSignatureDelivery(
                    harness: harness,
                    transcript: transcript,
                    acceptedInput: firstInput,
                    inputIndex: 0,
                    authorizationEvaluator: bchEvaluator,
                    authorizationVerificationKey: bchVerificationKey,
                    communicationKey: validFirstKey,
                    nonceIndex: 40_106,
                    messageIndex: 50_106,
                    signatureScalar: 107,
                    authorizationBinding: [UInt8](
                        repeating: 0xF2,
                        count: 32
                    )
                ),
                .anonymousBCHSignatureAdmissionRejected(
                    .invalidAuthorizationToken
                )
            ),
            (
                try makeBCHSignatureDelivery(
                    harness: harness,
                    transcript: transcript,
                    acceptedInput: firstInput,
                    inputIndex: 0,
                    authorizationEvaluator: bchEvaluator,
                    authorizationVerificationKey: bchVerificationKey,
                    communicationKey: validFirstKey,
                    nonceIndex: 40_107,
                    messageIndex: 50_107,
                    signatureScalar: 108,
                    transcriptRoot: [UInt8](repeating: 0xF3, count: 32)
                ),
                .anonymousBCHSignatureAdmissionRejected(
                    .invalidAuthorizationToken
                )
            ),
        ]
        for (delivery, failure) in invalidDeliveries {
            var invalidLedger = harness.ledger
            #expect(
                invalidLedger.receiveAnonymousBCHSignature(
                    delivery,
                    using: AcceptingBCHSignatureValidator()
                ) == [.inputRejected(failure)]
            )
            #expect(
                invalidLedger.receiveAnonymousBCHSignature(
                    validFirst,
                    using: AcceptingBCHSignatureValidator()
                ).contains { effect in
                    if case .anonymousBCHSignatureAdmitted = effect {
                        true
                    } else {
                        false
                    }
                }
            )
        }

        var semanticRejectionLedger = harness.ledger
        #expect(
            semanticRejectionLedger.receiveAnonymousBCHSignature(
                validFirst,
                using: RejectingBCHSignatureValidator()
            ) == [
                .inputRejected(
                    .anonymousBCHSignatureAdmissionRejected(
                        .anonymousBCHSignatureAdmissionRejected
                    )
                )
            ]
        )
        #expect(
            semanticRejectionLedger.receiveAnonymousBCHSignature(
                validFirst,
                using: AcceptingBCHSignatureValidator()
            ).contains { effect in
                if case .anonymousBCHSignatureAdmitted = effect {
                    true
                } else {
                    false
                }
            }
        )

        let sharedSender = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 6_000).compressed
        var oppositeParitySender = sharedSender
        oppositeParitySender[0] = sharedSender[0] == 0x02 ? 0x03 : 0x02
        var senderReuseLedger = harness.ledger
        let senderFirst = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: sharedSender,
            nonceIndex: 40_110,
            messageIndex: 50_110,
            signatureScalar: 110
        )
        let senderSecond = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: secondInput,
            inputIndex: 1,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: oppositeParitySender,
            nonceIndex: 40_111,
            messageIndex: 50_111,
            signatureScalar: 111
        )
        _ = senderReuseLedger.receiveAnonymousBCHSignature(
            senderFirst,
            using: AcceptingBCHSignatureValidator()
        )
        #expect(
            senderReuseLedger.receiveAnonymousBCHSignature(
                senderSecond,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .attemptTerminated(.failed(.anonymousCommunicationKeyReuse))
            ]
        )

        var mailboxReuseLedger = harness.ledger
        let mailboxFirst = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 6_100).compressed,
            nonceIndex: 40_112,
            messageIndex: 50_112,
            signatureScalar: 112
        )
        let mailboxSecond = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 1,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 6_101).compressed,
            nonceIndex: 40_113,
            messageIndex: 50_113,
            signatureScalar: 113
        )
        _ = mailboxReuseLedger.receiveAnonymousBCHSignature(
            mailboxFirst,
            using: AcceptingBCHSignatureValidator()
        )
        #expect(
            mailboxReuseLedger.receiveAnonymousBCHSignature(
                mailboxSecond,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .attemptTerminated(.failed(.anonymousRecipientIdentityReuse))
            ]
        )

        var inputConflictLedger = harness.ledger
        let inputFirst = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 6_200).compressed,
            nonceIndex: 40_114,
            messageIndex: 50_114,
            signatureScalar: 114
        )
        let inputSecond = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: secondInput,
            inputIndex: 0,
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 6_201).compressed,
            nonceIndex: 40_115,
            messageIndex: 50_115,
            signatureScalar: 115
        )
        _ = inputConflictLedger.receiveAnonymousBCHSignature(
            inputFirst,
            using: AcceptingBCHSignatureValidator()
        )
        #expect(
            inputConflictLedger.receiveAnonymousBCHSignature(
                inputSecond,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .attemptTerminated(
                    .failed(.anonymousBCHSignatureInputConflict(0))
                )
            ]
        )

        var setConstructionFailureLedger = harness.ledger
        for (inputIndex, acceptedInput) in acceptedInputs.enumerated() {
            let reportedIndex = inputIndex == 0
                ? UInt32(acceptedInputs.count)
                : UInt32(inputIndex)
            let delivery = try makeBCHSignatureDelivery(
                harness: harness,
                transcript: transcript,
                acceptedInput: acceptedInput,
                inputIndex: reportedIndex,
                authorizationEvaluator: bchEvaluator,
                authorizationVerificationKey: bchVerificationKey,
                communicationKey: try MosaicOpalV0WireContractValidator
                    .publicKeyFixture(scalar: 6_500 + inputIndex).compressed,
                nonceIndex: 40_130 + inputIndex,
                messageIndex: 50_130 + inputIndex,
                signatureScalar: 130 + inputIndex
            )
            let effects = setConstructionFailureLedger
                .receiveAnonymousBCHSignature(
                    delivery,
                    using: AcceptingBCHSignatureValidator()
                )
            if inputIndex == acceptedInputs.count - 1 {
                #expect(
                    effects.last == .attemptTerminated(
                        .failed(.bchSignatureSetConstructionFailed)
                    )
                )
            } else {
                #expect(effects.count == 1)
                guard case .anonymousBCHSignatureAdmitted = effects[0] else {
                    Issue.record("Expected a partial signature admission")
                    return
                }
            }
        }

        var firstDelivery: Ledger.AnonymousComponentDelivery?
        var readySignatureSet: Alpha.BCHSignatureSet?
        for (ordinal, inputIndex) in acceptedInputs.indices.reversed()
            .enumerated() {
            let acceptedInput = acceptedInputs[inputIndex]
            let communicationKey = try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 4_000 + inputIndex).compressed
            let delivery = try makeBCHSignatureDelivery(
                harness: harness,
                transcript: transcript,
                acceptedInput: acceptedInput,
                inputIndex: UInt32(inputIndex),
                authorizationEvaluator: bchEvaluator,
                authorizationVerificationKey: bchVerificationKey,
                communicationKey: communicationKey,
                nonceIndex: 40_000 + inputIndex,
                messageIndex: 50_000 + inputIndex,
                signatureScalar: 100 + inputIndex
            )
            firstDelivery = firstDelivery ?? delivery
            let effects = harness.ledger.receiveAnonymousBCHSignature(
                delivery,
                using: AcceptingBCHSignatureValidator()
            )
            #expect(effects.contains { effect in
                if case .anonymousBCHSignatureAdmitted = effect {
                    true
                } else {
                    false
                }
            })
            if ordinal == acceptedInputs.count - 1 {
                #expect(effects.contains { effect in
                    guard case let .bchSignatureSetReady(set) = effect else {
                        return false
                    }
                    return set.entries.map(\.inputIndex)
                        == (0 ..< acceptedInputs.count).map(UInt32.init)
                })
                readySignatureSet = effects.compactMap {
                    effect -> Alpha.BCHSignatureSet? in
                    guard case let .bchSignatureSetReady(set) = effect else {
                        return nil
                    }
                    return set
                }.first
            } else {
                #expect(!effects.contains { effect in
                    if case .bchSignatureSetReady = effect {
                        true
                    } else {
                        false
                    }
                })
            }
        }
        let duplicate = try #require(firstDelivery)
        let expiredDuplicate = Ledger.AnonymousComponentDelivery(
            attemptIdentifier: duplicate.attemptIdentifier,
            generationIdentifier: duplicate.generationIdentifier,
            envelope: duplicate.envelope,
            authenticatedOuterEventIdentity:
                duplicate.authenticatedOuterEventIdentity,
            authenticatedRecipientEventIdentity:
                duplicate.authenticatedRecipientEventIdentity,
            authenticatedMessageIdentifier:
                duplicate.authenticatedMessageIdentifier,
            currentUnixSeconds: 1_900_000_000
        )
        #expect(
            harness.ledger.receiveAnonymousBCHSignature(
                expiredDuplicate,
                using: RejectingBCHSignatureValidator()
            ) == [.exactDuplicateIgnored]
        )
        let signatureSet = try #require(readySignatureSet)
        let completePayload = try makeCompletePayload(
            transcript: transcript,
            signatureSet: signatureSet
        )
        let signatureRun = try Fixture.aggregateRun(
            canonicalBytes: signatureSet.canonicalBytes,
            kind: .bchSignatureSet,
            sender: harness.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: portableRun.nextSequence,
            harness: harness
        )
        let completeRun = try Fixture.aggregateRun(
            canonicalBytes: completePayload.canonicalBytes,
            kind: .completeTransaction,
            sender: harness.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: portableRun.nextSequence,
            harness: harness
        )

        var completeFirstLedger = harness.ledger
        let completeFirstEffects = Fixture.admit(
            completeRun,
            to: &completeFirstLedger
        )
        #expect(
            completeFirstEffects.last
                == .attemptTerminated(
                    .failed(.completeTransactionPrerequisiteMissing)
                )
        )
        #expect(!containsCompletionValidationRequest(completeFirstEffects))

        var mismatchedEntries = signatureSet.entries
        var mismatchedSignature = mismatchedEntries[0].signature
        mismatchedSignature[0] ^= 0x01
        mismatchedEntries[0] = try .init(
            inputIndex: mismatchedEntries[0].inputIndex,
            signature: mismatchedSignature,
            publicKey: mismatchedEntries[0].publicKey
        )
        let mismatchedSet = try Alpha.BCHSignatureSet(
            roundIdentifier: signatureSet.roundIdentifier,
            transcriptRoot: signatureSet.transcriptRoot,
            entries: mismatchedEntries,
            expectedInputCount: signatureSet.entries.count
        )
        let mismatchedSignatureRun = try Fixture.aggregateRun(
            canonicalBytes: mismatchedSet.canonicalBytes,
            kind: .bchSignatureSet,
            sender: harness.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: portableRun.nextSequence,
            harness: harness
        )
        var mismatchedSignatureLedger = harness.ledger
        let mismatchedSignatureEffects = Fixture.admit(
            mismatchedSignatureRun,
            to: &mismatchedSignatureLedger
        )
        #expect(
            mismatchedSignatureEffects.last
                == .attemptTerminated(
                    .failed(.bchSignatureSetDoesNotMatchAnonymousAdmissions)
                )
        )
        #expect(!containsCompletionValidationRequest(mismatchedSignatureEffects))

        var mismatchedPayloadLedger = harness.ledger
        #expect(
            Fixture.admit(signatureRun, to: &mismatchedPayloadLedger)
                .contains(.bchSignatureSetAdmitted(signatureSet))
        )
        let mismatchedPayload = try makeCompletePayload(
            transcript: transcript,
            signatureSet: signatureSet,
            mutateFirstSignature: true
        )
        let mismatchedCompleteRun = try Fixture.aggregateRun(
            canonicalBytes: mismatchedPayload.canonicalBytes,
            kind: .completeTransaction,
            sender: harness.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: signatureRun.nextSequence,
            harness: harness
        )
        let mismatchedPayloadEffects = Fixture.admit(
            mismatchedCompleteRun,
            to: &mismatchedPayloadLedger
        )
        #expect(
            mismatchedPayloadEffects.last
                == .attemptTerminated(
                    .failed(.completeTransactionSignatureSetMismatch)
                )
        )
        #expect(!containsCompletionValidationRequest(mismatchedPayloadEffects))

        let extra = try makeBCHSignatureDelivery(
            harness: harness,
            transcript: transcript,
            acceptedInput: firstInput,
            inputIndex: UInt32(acceptedInputs.count),
            authorizationEvaluator: bchEvaluator,
            authorizationVerificationKey: bchVerificationKey,
            communicationKey: try MosaicOpalV0WireContractValidator
                .publicKeyFixture(scalar: 7_000).compressed,
            nonceIndex: 40_120,
            messageIndex: 50_120,
            signatureScalar: 120
        )
        #expect(
            harness.ledger.receiveAnonymousBCHSignature(
                extra,
                using: AcceptingBCHSignatureValidator()
            ) == [
                .attemptTerminated(
                    .failed(.anonymousBCHSignatureLimitExceeded)
                )
            ]
        )
        #expect(
            harness.ledger.receiveAnonymousBCHSignature(
                duplicate,
                using: RejectingBCHSignatureValidator()
            ) == [.exactDuplicateIgnored]
        )
        #expect(
            harness.ledger.receiveAnonymousBCHSignature(
                extra,
                using: AcceptingBCHSignatureValidator()
            ) == [.inputRejected(.inputAfterTermination)]
        )
    }

    private struct PreparedTranscript {
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        let nextConductorSequence: UInt64
        let nextContributorSequence: UInt64
    }

    private func makeCompletePayload(
        transcript: Ledger.Transcript,
        signatureSet: Alpha.BCHSignatureSet,
        mutateFirstSignature: Bool = false
    ) throws -> Alpha.CompleteTransactionPayload {
        var transaction = transcript.transaction
        for (offset, entry) in signatureSet.entries.enumerated() {
            var signature = entry.signature
            if mutateFirstSignature, offset == 0 {
                signature[0] ^= 0x01
            }
            let unlockingScript = [UInt8(0x41)] + signature
                + [0x41, 0x21] + entry.publicKey
            transaction = try transaction.settingUnlockingScript(
                unlockingScript,
                at: Int(entry.inputIndex)
            )
        }
        return try .init(
            roundIdentifier: signatureSet.roundIdentifier,
            transcriptRoot: signatureSet.transcriptRoot,
            completeTransaction: try .init(
                transactionBytes: transaction.serialize()
            )
        )
    }

    private func containsCompletionValidationRequest(
        _ effects: [Ledger.Effect]
    ) -> Bool {
        effects.contains { effect in
            if case .completeTransactionValidationRequired = effect {
                true
            } else {
                false
            }
        }
    }

    private func makeBCHSignatureDelivery(
        harness: Fixture.Harness,
        transcript: Ledger.Transcript,
        acceptedInput: Alpha.AnonymousComponentAdmissionValidation,
        inputIndex: UInt32,
        authorizationEvaluator: OpalFusion.Mosaic.OpalV0
            .AuthorizationEvaluator,
        authorizationVerificationKey: OpalCrypto.RSABSSA.VerificationKey,
        communicationKey: [UInt8],
        nonceIndex: Int,
        messageIndex: Int,
        signatureScalar: Int,
        authorizationToken suppliedAuthorizationToken:
            Alpha.AuthorizationToken? = nil,
        authorizationPurpose: Alpha.AuthorizationPurpose = .bchSignature,
        authorizationBinding: [UInt8]? = nil,
        transcriptRoot: [UInt8]? = nil,
        phase: OpalFusion.Mosaic.Attempt.Phase = .bchSigning,
        sequence: UInt64 = 1,
        roundIdentifier: [UInt8]? = nil,
        recipientEventIdentity: [UInt8]? = nil,
        expiryUnixSeconds: UInt64 = 1_800_000_060,
        currentUnixSeconds: UInt64 = 1_800_000_000
    ) throws -> Ledger.AnonymousComponentDelivery {
        let roundIdentifier = roundIdentifier
            ?? harness.manifest.core.roundIdentifier
        let authorizationToken: Alpha.AuthorizationToken
        if let suppliedAuthorizationToken {
            authorizationToken = suppliedAuthorizationToken
        } else {
            let authorizationInput = try Alpha.AuthorizationTokenInput(
                roundIdentifier: roundIdentifier,
                keyIdentifier: [UInt8](
                    authorizationVerificationKey.keyIdentifier
                ),
                purpose: authorizationPurpose,
                nonce: MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                    nonceIndex
                ),
                binding: authorizationBinding
                    ?? acceptedInput.authorizationSpentIdentifier
            )
            let authorizationRequest = try Alpha.AuthorizationRequest(
                input: authorizationInput,
                using: authorizationVerificationKey
            )
            authorizationToken = try authorizationRequest.finalize(
                authorizationEvaluator.evaluate(
                    authorizationRequest.blindedMessage
                )
            )
        }
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: scalarBytes(signatureScalar)
        )
        let signature = try signingKey.signSchnorr(
            digest: .init(
                rawRepresentation: Data(
                    MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                        45_000 + Int(inputIndex)
                    )
                )
            )
        )
        let submission = try Alpha.BCHSignatureSubmission(
            transcriptRoot:
                transcriptRoot ?? transcript.transcriptRoot.validatedBytes,
            authorizationToken: authorizationToken,
            entry: try .init(
                inputIndex: inputIndex,
                signature: [UInt8](signature.rawRepresentation),
                publicKey: [UInt8](
                    signingKey.publicKey.compressedRepresentation
                )
            )
        )
        let recipientEventIdentity = recipientEventIdentity
            ?? acceptedInput.recipientEventIdentity
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: roundIdentifier,
            phase: phase,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: recipientEventIdentity,
            sequence: sequence,
            payloadType: .bchSignatureSubmission,
            expiryUnixSeconds: expiryUnixSeconds,
            payload: Alpha.CanonicalWireCodec
                .encodeBCHSignatureSubmission(submission)
        )
        return .init(
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            envelope: envelope,
            authenticatedOuterEventIdentity: Array(
                communicationKey.dropFirst()
            ),
            authenticatedRecipientEventIdentity: recipientEventIdentity,
            authenticatedMessageIdentifier: try .init(
                bytes: MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                    messageIndex
                )
            ),
            currentUnixSeconds: currentUnixSeconds
        )
    }

    private func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var result = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { result.append(contentsOf: $0) }
        return result
    }

    private struct LocalAuthorizationMaterial {
        let material: Alpha.LocalContributionMaterial
        let playerCommit: Alpha.PlayerCommit
        let responseSet: Alpha.AuthorizationResponseSet
        let validation: Alpha.AuthorizationResponseSetMaterialValidation
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

    private struct AcceptingBCHSignatureValidator:
        Alpha.AnonymousBCHSignatureAdmissionValidating
    {
        func validateBCHSignatureAdmission(
            submission _: Alpha.BCHSignatureSubmission,
            acceptedInputComponent _: OpalFusion.Mosaic.OpalV0.Component,
            transcript _: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) throws {}
    }

    private struct RejectingBCHSignatureValidator:
        Alpha.AnonymousBCHSignatureAdmissionValidating
    {
        struct Rejection: Error {}

        func validateBCHSignatureAdmission(
            submission _: Alpha.BCHSignatureSubmission,
            acceptedInputComponent _: OpalFusion.Mosaic.OpalV0.Component,
            transcript _: OpalFusion.Mosaic.OpalV0
                .UnsignedTransactionTranscript
        ) throws {
            throw Rejection()
        }
    }

    private struct PreparedConductorCommitments {
        let preparation: MosaicUnsignedTransactionTranscriptFixtures.Prepared
        let nextConductorSequence: UInt64
        let nextContributorSequenceByIdentity: [Ledger.ControlIdentity: UInt64]
        let authorizationMaterial: LocalAuthorizationMaterial?
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
        harness: inout Fixture.Harness,
        evaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
    ) throws -> PreparedTranscript {
        var conductorSequence = try admitManifestAndAdvanceWallet(
            harness: &harness
        )
        let materialized = try MosaicMainnetAlphaFixtures
            .makeMaterializedPreparation(
                election: harness.election,
                manifest: harness.manifest,
                attemptIdentifier: harness.attemptIdentifier,
                generationIdentifier: harness.generationIdentifier,
                localContributor: harness.localControlIdentity,
                localMaterialIdentifier: harness.materialIdentifier
            )
        let preparation = materialized.prepared
        let localContributionMaterial = try #require(
            materialized.materials[harness.localControlIdentity]
        )
        let verificationKey = try #require(evaluator.verificationKey)
        try #require(
            verificationKey == harness.manifest.core
                .componentAuthorizationVerificationKey
        )
        let material = try makeLocalAuthorizationMaterial(
            material: localContributionMaterial,
            evaluator: evaluator
        )
        let contributor = harness.localControlIdentity
        let playerCommit = material.playerCommit
        let playerCommits = try harness.manifest.core.orderedContributors.map {
            try #require(materialized.materials[$0]?.playerCommit)
        }
        let playerCommitRun = try Fixture.aggregateRun(
            canonicalBytes: playerCommit.canonicalBytes,
            kind: .playerCommit,
            sender: contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: harness
        )
        try #require(
            Fixture.admit(playerCommitRun, to: &harness.ledger)
                .contains(.playerCommitAdmitted(playerCommit))
        )
        let responseSet = material.responseSet
        let validation = material.validation
        for (index, commit) in playerCommits.enumerated() {
            let publishedSet: Alpha.AuthorizationResponseSet
            if commit.contributor == contributor {
                publishedSet = responseSet
            } else {
                publishedSet = try Fixture.makeAuthorizationResponseSet(
                    playerCommit: commit,
                    byteSeed: UInt8(index + 1)
                )
            }
            let responseRun = try Fixture.aggregateRun(
                canonicalBytes: publishedSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: harness.election.result.roster.conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                harness: harness
            )
            let effects = Fixture.admit(responseRun, to: &harness.ledger)
            try #require(
                effects.contains(
                    .authorizationResponseSetAdmitted(publishedSet)
                )
            )
            if commit.contributor == contributor {
                try #require(
                    effects.contains(
                        .authorizationResponseSetValidationRequired(
                            responseSet,
                            playerCommit: playerCommit
                        )
                    )
                )
                if index < playerCommits.count - 1 {
                    var locallyValidatedBeforeCompleteStream = harness.ledger
                    _ = locallyValidatedBeforeCompleteStream.apply(
                        input: .authorizationResponseSetValidated(
                            .init(validation: validation)
                        )
                    )
                    #expect(
                        try synchronize(
                            &locallyValidatedBeforeCompleteStream,
                            to: .groupedCommitment
                        ) == [
                            .attemptTerminated(
                                .failed(
                                    .phaseAdvancePrerequisiteMissing(
                                        .groupedCommitment
                                    )
                                )
                            )
                        ]
                    )
                }
            }
            conductorSequence = responseRun.nextSequence
        }
        var unvalidatedLedger = harness.ledger
        #expect(
            try synchronize(&unvalidatedLedger, to: .groupedCommitment)
                == [
                    .attemptTerminated(
                        .failed(
                            .phaseAdvancePrerequisiteMissing(
                                .groupedCommitment
                            )
                        )
                    )
                ]
        )
        var foreignAttemptLedger = try Ledger(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xD1, count: 32)
            ),
            generationIdentifier: harness.generationIdentifier,
            materialIdentifier: harness.materialIdentifier,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
        #expect(
            foreignAttemptLedger.apply(
                input: .authorizationResponseSetValidated(
                    .init(validation: validation)
                )
            ) == [.inputRejected(.attemptIdentifierMismatch)]
        )
        var foreignGenerationLedger = try Ledger(
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xD2, count: 32)
            ),
            materialIdentifier: harness.materialIdentifier,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
        #expect(
            foreignGenerationLedger.apply(
                input: .authorizationResponseSetValidated(
                    .init(validation: validation)
                )
            ) == [.inputRejected(.generationIdentifierMismatch)]
        )
        var foreignMaterialLedger = try Ledger(
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            materialIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xD3, count: 32)
            ),
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
        #expect(
            foreignMaterialLedger.apply(
                input: .authorizationResponseSetValidated(
                    .init(validation: validation)
                )
            ) == [.inputRejected(.materialIdentifierMismatch)]
        )
        try #require(
            harness.ledger.apply(
                input: .authorizationResponseSetValidated(
                    .init(validation: validation)
                )
            ) == [
                .authorizationResponsesValidated(validation)
            ]
        )
        let groupedCommitmentEffects = try synchronize(
            &harness.ledger,
            to: .groupedCommitment
        )
        try #require(
            groupedCommitmentEffects == [.phaseAdvanced(.groupedCommitment)]
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
            nextConductorSequence: componentRun.nextSequence,
            nextContributorSequence: playerCommitRun.nextSequence
        )
    }

    private func makeLocalAuthorizationMaterial(
        material: Alpha.LocalContributionMaterial,
        evaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
    ) throws -> LocalAuthorizationMaterial {
        let componentVerificationKey = try #require(evaluator.verificationKey)
        let bchSignatureEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let bchSignatureVerificationKey = try #require(
            bchSignatureEvaluator.verificationKey
        )
        try #require(
            componentVerificationKey
                == material.manifest.core
                    .componentAuthorizationVerificationKey
        )
        try #require(
            bchSignatureVerificationKey
                == material.manifest.core
                    .bchSignatureAuthorizationVerificationKey
        )
        let componentResponses = try material.slots.enumerated().map {
            slot, materialSlot in
            let request = materialSlot.componentAuthorizationRequest
            return try OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload(
                slot: slot,
                blindSignature: evaluator.evaluate(request.blindedMessage)
            )
        }
        let bchSignatureResponses = try material.slots.enumerated().map {
            slot, materialSlot in
            let request = materialSlot.bchSignatureAuthorizationRequest
            return try OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload(
                slot: slot,
                blindSignature: bchSignatureEvaluator.evaluate(
                    request.blindedMessage
                )
            )
        }
        let responseSet = try Alpha.AuthorizationResponseSet(
            roundIdentifier: material.manifest.core.roundIdentifier,
            contributor: material.contributor,
            playerCommitDigest: material.playerCommit.digest,
            componentAuthorizationResponses: componentResponses,
            bchSignatureAuthorizationResponses: bchSignatureResponses
        )
        let validation = try Alpha.AuthorizationResponseSetMaterialValidation(
            validating: responseSet,
            material: material
        )
        return .init(
            material: material,
            playerCommit: material.playerCommit,
            responseSet: responseSet,
            validation: validation
        )
    }

    private func prepareConductorCommitments(
        harness: inout Fixture.Harness,
        materialized: Bool = false
    ) throws -> PreparedConductorCommitments {
        var conductorSequence = try admitManifestAndAdvanceWallet(
            harness: &harness
        )
        let preparation: MosaicUnsignedTransactionTranscriptFixtures.Prepared
        let commits: [Alpha.PlayerCommit]
        let authorizationMaterial: LocalAuthorizationMaterial?
        if materialized {
            let localContributor = try #require(
                harness.manifest.core.orderedContributors.first
            )
            let materializedPreparation = try MosaicMainnetAlphaFixtures
                .makeMaterializedPreparation(
                    election: harness.election,
                    manifest: harness.manifest,
                    attemptIdentifier: harness.attemptIdentifier,
                    generationIdentifier: harness.generationIdentifier,
                    localContributor: localContributor,
                    localMaterialIdentifier: harness.materialIdentifier
                )
            preparation = materializedPreparation.prepared
            commits = try harness.manifest.core.orderedContributors.map {
                try #require(
                    materializedPreparation.materials[$0]?.playerCommit
                )
            }
            authorizationMaterial = try makeLocalAuthorizationMaterial(
                material: try #require(
                    materializedPreparation.materials[localContributor]
                ),
                evaluator: MosaicMainnetAlphaFixtures.authorizationEvaluator()
            )
        } else {
            preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
                roster: harness.election.result.roster,
                manifest: harness.manifest.binding,
                profile: .opalMainnetAlpha
            )
            commits = try Fixture.makePlayerCommits(
                harness: harness,
                commitmentSet: preparation.commitmentSet
            )
            authorizationMaterial = nil
        }
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
        for (index, commit) in commits.enumerated() {
            let responseSet = if commit.contributor
                == authorizationMaterial?.material.contributor {
                try #require(authorizationMaterial?.responseSet)
            } else {
                try Fixture.makeAuthorizationResponseSet(
                    playerCommit: commit,
                    byteSeed: UInt8(index + 1)
                )
            }
            let run = try Fixture.aggregateRun(
                canonicalBytes: responseSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: harness.election.result.roster.conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                harness: harness
            )
            let effects = Fixture.admit(run, to: &harness.ledger)
            try #require(
                effects.contains(.authorizationResponseSetAdmitted(responseSet))
            )
            conductorSequence = run.nextSequence
        }
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
                nextContributorSequenceByIdentity,
            authorizationMaterial: authorizationMaterial
        )
    }

}
