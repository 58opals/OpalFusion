// MosaicMainnetAlphaRuntimeSessionValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha runtime session")
struct MosaicMainnetAlphaRuntimeSessionValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Session = Alpha.RuntimeSession

    private struct Harness {
        let admission: Fixture.Harness
        let materialIdentifier: OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier
        var session: Session
    }

    private struct LocalAuthorizationMaterial {
        let material: Alpha.LocalContributionMaterial
        let playerCommit: Alpha.PlayerCommit
        let responseSet: Alpha.AuthorizationResponseSet
        let validation: Alpha.AuthorizationResponseSetMaterialValidation
    }

    private struct PreparedTranscript {
        let transcript: OpalFusion.Mosaic.OpalV0.UnsignedTransactionTranscript
        let nextConductorSequence: UInt64
    }

    private struct PreparedGroupedCommitment {
        let preparation: MosaicUnsignedTransactionTranscriptFixtures.Prepared
        let localPlayerCommit: Alpha.PlayerCommit
        let nextConductorSequence: UInt64
    }

    enum ReservationPublicationSubstitution: CaseIterable, Sendable {
        case generation
        case material
        case contributor
        case manifest
        case playerCommit
    }

    private struct ReservationReferenceValidator:
        Session.ReservationPublicationValidating
    {
        struct Rejection: Error {}

        let expectedReference: OpalFusion.Host.MosaicReservationReference

        func validateReservationPublication(
            _ request: Session.ReservationPublicationRequest
        ) throws {
            guard request.reservationReference == expectedReference else {
                throw Rejection()
            }
        }
    }

    private struct RejectingReservationPublicationValidator:
        Session.ReservationPublicationValidating
    {
        struct Rejection: Error {}

        func validateReservationPublication(
            _: Session.ReservationPublicationRequest
        ) throws {
            throw Rejection()
        }
    }

    @Test("Bridge binds every supported contributor roster", arguments: [7, 8, 9])
    func bindEverySupportedRoster(candidateCount: Int) throws {
        var harness = try makeHarness(candidateCount: candidateCount)
        let effects = try admitManifest(to: &harness)

        #expect(harness.session.state == .active(.walletReservation))
        #expect(
            effects.contains(
                .localAttempt(
                    .walletReservationEligible(
                        contributor: harness.admission.localControlIdentity,
                        materialIdentifier: harness.materialIdentifier,
                        manifest: harness.admission.manifest.binding
                    )
                )
            )
        )
        #expect(
            harness.admission.election.result.roster.contributors.count
                == candidateCount - 1
        )
    }

    @Test("Conductor bridge never emits wallet reservation eligibility")
    func keepConductorNonContributing() throws {
        var harness = try makeHarness(localRole: .conductor)
        let effects = try admitManifest(to: &harness)

        #expect(harness.session.state == .active(.walletReservation))
        #expect(
            !effects.contains { effect in
                guard case .localAttempt(.walletReservationEligible) = effect else {
                    return false
                }
                return true
            }
        )
    }

    @Test("Bridge construction rejects a different proposal roster")
    func rejectProposalMismatch() throws {
        let first = try Fixture.makeHarness(localRole: .contributor)
        let second = try Fixture.makeHarness(
            candidateCount: 8,
            localRole: .contributor
        )

        #expect(throws: Session.InitializationError.proposalValidationMismatch) {
            _ = try Session(
                validatedAttempt: Fixture.makeValidatedAttempt(
                    election: first.election
                ),
                attemptIdentifier: first.attemptIdentifier,
                generationIdentifier: first.generationIdentifier,
                materialIdentifier: .init(
                    opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
                ),
                localControlIdentity: first.localControlIdentity,
                proposalValidation: second.proposalValidation
            )
        }
    }

    @Test(
        "Bridge reaches the exact transcript only after reservation-publication binding",
        .timeLimit(.minutes(2))
    )
    func bridgeThroughTranscriptAgreement() throws {
        let evaluator = try MosaicMainnetAlphaFixtures.authorizationEvaluator()
        let verificationKey = try #require(evaluator.verificationKey)
        var harness = try makeHarness(verificationKey: verificationKey)
        let prepared = try driveToTranscript(
            harness: &harness,
            evaluator: evaluator
        )

        #expect(harness.session.state == .active(.transcriptAgreement))
        #expect(
            harness.session.localAttemptState
                == .transcriptAgreement(
                    roster: harness.admission.election.result.roster,
                    transcript: prepared.transcript
                )
        )
        #expect(
            harness.session.admissionLedgerState
                == .active(.transcriptAgreement(prepared.transcript))
        )
    }

    @Test(
        "Contributor requires every local commitment in the published set",
        .timeLimit(.minutes(2))
    )
    func rejectLocalCommitmentSubstitution() throws {
        let evaluator = try MosaicMainnetAlphaFixtures.authorizationEvaluator()
        let verificationKey = try #require(evaluator.verificationKey)
        var harness = try makeHarness(verificationKey: verificationKey)
        let prepared = try driveToGroupedCommitment(
            harness: &harness,
            evaluator: evaluator
        )
        var commitments = prepared.preparation.commitmentSet.commitments
        let localCommitment = prepared.localPlayerCommit
            .groupedCommitment.commitments[0]
        let localIndex = try #require(
            commitments.firstIndex(of: localCommitment)
        )
        var substitutedDigest = localCommitment.saltedComponentDigest
        substitutedDigest[substitutedDigest.startIndex] ^= 0x01
        commitments[localIndex] = try .init(
            saltedComponentDigest: substitutedDigest,
            amountCommitment: localCommitment.amountCommitment,
            communicationPublicKey: localCommitment.communicationPublicKey
        )
        let substitutedSet = try OpalFusion.Mosaic.OpalV0.CommitmentSet(
            profile: .opalMainnetAlpha,
            commitments: commitments
        )
        let run = try Fixture.aggregateRun(
            canonicalBytes: substitutedSet.canonicalBytes,
            kind: .commitmentSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: prepared.nextConductorSequence,
            harness: harness.admission
        )
        let effects = admit(run, to: &harness.session)

        expectReservationFailure(
            effects,
            harness: harness,
            during: .groupedCommitment,
            failure: .localCommitmentSetMismatch
        )
    }

    @Test(
        "Portable acknowledgements remain fail closed before BCH signing",
        .timeLimit(.minutes(2))
    )
    func keepBCHSigningClosed() throws {
        let evaluator = try MosaicMainnetAlphaFixtures.authorizationEvaluator()
        let verificationKey = try #require(evaluator.verificationKey)
        var harness = try makeHarness(verificationKey: verificationKey)
        let prepared = try driveToTranscript(
            harness: &harness,
            evaluator: evaluator
        )
        let inclusion = try MosaicUnsignedTransactionTranscriptFixtures
            .makeTranscriptInclusionValidation(
                attemptIdentifier: harness.admission.attemptIdentifier,
                generationIdentifier: harness.admission.generationIdentifier,
                contributor: harness.admission.localControlIdentity,
                materialIdentifier: harness.materialIdentifier,
                transcript: prepared.transcript
            )
        let inclusionEffects = harness.session.apply(
            input: .transcriptInclusionValidated(inclusion)
        )
        #expect(
            inclusionEffects.contains {
                guard case .localAttempt(.preSignAcknowledgementRequired) = $0 else {
                    return false
                }
                return true
            }
        )

        let acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: harness.admission.election.result.roster.contributors,
                binding: harness.admission.manifest.binding,
                transcriptRoot: prepared.transcript.transcriptRoot,
                profile: .opalMainnetAlpha
            )
        let submissions = try acknowledgements.sorted {
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
        let acknowledgementSet = try Alpha.PreSignAcknowledgementSet(
            roundIdentifier: harness.admission.manifest.core.roundIdentifier,
            transcriptRoot: prepared.transcript.transcriptRoot.validatedBytes,
            roster: harness.admission.election.result.roster,
            submissions: submissions
        )
        let run = try Fixture.aggregateRun(
            canonicalBytes: acknowledgementSet.canonicalBytes,
            kind: .preSignAcknowledgementSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .transcriptAgreement,
            sequence: prepared.nextConductorSequence,
            harness: harness.admission
        )
        let effects = admit(run, to: &harness.session)

        #expect(
            effects.contains(
                .admission(
                    .preSignAcknowledgementSetAdmitted(acknowledgementSet)
                )
            )
        )
        #expect(
            !effects.contains { effect in
                guard case .localAttempt(.bchSigningEligible) = effect else {
                    return false
                }
                return true
            }
        )
        #expect(harness.session.state == .active(.transcriptAgreement))
        #expect(
            harness.session.localAttemptState
                == .transcriptAgreement(
                    roster: harness.admission.election.result.roster,
                    transcript: prepared.transcript
                )
        )
        #expect(!OpalFusion.Mosaic.Profile.opalMainnetAlpha.supportsRuntimeSessionDriver)
    }

    @Test("Reservation publication rejects foreign attempt material")
    func rejectForeignReservationPublication() throws {
        var harness = try makeHarness()
        _ = try admitManifest(to: &harness)
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.admission.election.result.roster,
            manifest: harness.admission.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let playerCommit = try localPlayerCommit(
            harness: harness,
            commitmentSet: preparation.commitmentSet
        )
        let request = try reservationPublicationRequest(
            harness: harness,
            playerCommit: playerCommit,
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xF1, count: 32)
            )
        )
        let validation = try Session.ReservationPublicationValidation(
            validating: request,
            using: ReservationReferenceValidator(
                expectedReference: request.reservationReference
            )
        )
        let effects = harness.session.apply(
            input: .reservationPublicationValidated(validation)
        )

        #expect(
            effects.suffix(3) == [
                .localAttempt(
                    .walletReservationReleaseRequired(
                        contributor: harness.admission.localControlIdentity,
                        materialIdentifier: harness.materialIdentifier
                    )
                ),
                .localAttempt(
                    .attemptTerminated(
                        .failed(
                            .aborted(
                                during: .walletReservation,
                                reason: .invalidAuthenticatedMessage
                            )
                        )
                    )
                ),
                .sessionTerminated(
                    .failed(.reservationPublicationMismatch)
                ),
            ]
        )
        #expect(
            harness.session.admissionLedgerState
                == .terminal(.failed(.runtimeSessionBridgeMismatch))
        )
    }

    @Test(
        "Reservation publication rejects every substituted binding",
        arguments: ReservationPublicationSubstitution.allCases
    )
    func rejectReservationPublicationSubstitution(
        _ substitution: ReservationPublicationSubstitution
    ) throws {
        var harness = try makeHarness()
        _ = try admitManifest(to: &harness)
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.admission.election.result.roster,
            manifest: harness.admission.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let correctPlayerCommit = try localPlayerCommit(
            harness: harness,
            commitmentSet: preparation.commitmentSet
        )
        var generationIdentifier = harness.admission.generationIdentifier
        var materialIdentifier = harness.materialIdentifier
        var contributor = harness.admission.localControlIdentity
        var manifest = harness.admission.manifest
        var playerCommit = correctPlayerCommit

        switch substitution {
        case .generation:
            generationIdentifier = .init(
                opaqueBytes: [UInt8](repeating: 0xF2, count: 32)
            )
        case .material:
            materialIdentifier = .init(
                opaqueBytes: [UInt8](repeating: 0xF3, count: 32)
            )
        case .contributor:
            contributor = harness.admission.election.result.roster.conductor
        case .manifest:
            manifest = try makeHarness(candidateCount: 8).admission.manifest
        case .playerCommit:
            let run = try Fixture.aggregateRun(
                canonicalBytes: correctPlayerCommit.canonicalBytes,
                kind: .playerCommit,
                sender: harness.admission.localControlIdentity,
                phase: .walletReservation,
                sequence: 0,
                harness: harness.admission
            )
            _ = admit(run, to: &harness.session)
            playerCommit = try conflictingPlayerCommit(
                with: correctPlayerCommit
            )
        }

        let request = try reservationPublicationRequest(
            harness: harness,
            playerCommit: playerCommit,
            generationIdentifier: generationIdentifier,
            materialIdentifier: materialIdentifier,
            contributor: contributor,
            manifest: manifest
        )
        let validation = try Session.ReservationPublicationValidation(
            validating: request,
            using: ReservationReferenceValidator(
                expectedReference: request.reservationReference
            )
        )
        let effects = harness.session.apply(
            input: .reservationPublicationValidated(validation)
        )

        expectReservationFailure(
            effects,
            harness: harness,
            during: .walletReservation,
            failure: .reservationPublicationMismatch
        )
    }

    @Test("A later conflicting PlayerCommit invalidates sealed publication")
    func rejectLateConflictingPlayerCommit() throws {
        var harness = try makeHarness()
        _ = try admitManifest(to: &harness)
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.admission.election.result.roster,
            manifest: harness.admission.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let playerCommit = try localPlayerCommit(
            harness: harness,
            commitmentSet: preparation.commitmentSet
        )
        let request = try reservationPublicationRequest(
            harness: harness,
            playerCommit: playerCommit
        )
        let validation = try Session.ReservationPublicationValidation(
            validating: request,
            using: ReservationReferenceValidator(
                expectedReference: request.reservationReference
            )
        )
        #expect(
            harness.session.apply(
                input: .reservationPublicationValidated(validation)
            ) == [.reservationPublicationAccepted(request.reservationReference)]
        )

        let conflicting = try conflictingPlayerCommit(with: playerCommit)
        let run = try Fixture.aggregateRun(
            canonicalBytes: conflicting.canonicalBytes,
            kind: .playerCommit,
            sender: harness.admission.localControlIdentity,
            phase: .walletReservation,
            sequence: 0,
            harness: harness.admission
        )
        let effects = admit(run, to: &harness.session)

        expectReservationFailure(
            effects,
            harness: harness,
            during: .walletReservation,
            failure: .reservationPublicationMismatch
        )
    }

    @Test("Reservation publication validator rejects a foreign host reference")
    func rejectForeignReservationReference() throws {
        let harness = try makeHarness()
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.admission.election.result.roster,
            manifest: harness.admission.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let expectedReference = reservationReference()
        let request = try reservationPublicationRequest(
            harness: harness,
            playerCommit: try localPlayerCommit(
                harness: harness,
                commitmentSet: preparation.commitmentSet
            ),
            reservationReference: reservationReference(
                finalByte: 0xC2,
                generation: 2
            )
        )

        #expect(
            throws: Session.ReservationPublicationValidation.ValidationError
                .rejected
        ) {
            _ = try Session.ReservationPublicationValidation(
                validating: request,
                using: ReservationReferenceValidator(
                    expectedReference: expectedReference
                )
            )
        }
    }

    @Test("Reservation publication validation cannot be self-asserted")
    func rejectUnsealedReservationPublication() throws {
        let harness = try makeHarness()
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: harness.admission.election.result.roster,
            manifest: harness.admission.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let request = try reservationPublicationRequest(
            harness: harness,
            playerCommit: try localPlayerCommit(
                harness: harness,
                commitmentSet: preparation.commitmentSet
            )
        )

        #expect(throws: Session.ReservationPublicationValidation.ValidationError.rejected) {
            _ = try Session.ReservationPublicationValidation(
                validating: request,
                using: RejectingReservationPublicationValidator()
            )
        }
    }

    @Test("Cancellation releases before the bridge terminates")
    func cancelWithOrderedReservationDisposition() throws {
        var harness = try makeHarness()
        _ = try admitManifest(to: &harness)
        let effects = harness.session.apply(input: .cancel)

        #expect(
            effects == [
                .localAttempt(
                    .walletReservationReleaseRequired(
                        contributor: harness.admission.localControlIdentity,
                        materialIdentifier: harness.materialIdentifier
                    )
                ),
                .localAttempt(
                    .attemptTerminated(
                        .cancelled(.requested(during: .walletReservation))
                    )
                ),
                .sessionTerminated(.cancelled(during: .walletReservation)),
            ]
        )
        #expect(
            harness.session.apply(input: .cancel)
                == [.inputRejected(.inputAfterTermination)]
        )
    }

    @Test("Retry terminates one bridge and requires fresh material")
    func rejectInPlaceRetry() throws {
        var harness = try makeHarness()
        _ = try admitManifest(to: &harness)
        let effects = harness.session.apply(input: .retryRequested)

        #expect(
            effects.last
                == .sessionTerminated(.failed(.inPlaceRetryNotPermitted))
        )
        #expect(
            harness.session.state
                == .terminal(.failed(.inPlaceRetryNotPermitted))
        )
    }

    private func makeHarness(
        candidateCount: Int = 7,
        localRole: OpalFusion.Mosaic.Role = .contributor,
        verificationKey: OpalCrypto.RSABSSA.VerificationKey? = nil
    ) throws -> Harness {
        let bchSignatureVerificationKey: OpalCrypto.RSABSSA.VerificationKey?
        if verificationKey == nil {
            bchSignatureVerificationKey = nil
        } else {
            bchSignatureVerificationKey = try MosaicMainnetAlphaFixtures
                .bchSignatureAuthorizationEvaluator().verificationKey
        }
        let admission = try Fixture.makeHarness(
            candidateCount: candidateCount,
            localRole: localRole,
            verificationKey: verificationKey,
            bchSignatureVerificationKey: bchSignatureVerificationKey
        )
        let materialIdentifier = OpalFusion.Mosaic.LocalAttempt.MaterialIdentifier(
            opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
        )
        let session = try Session(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            proposalValidation: admission.proposalValidation
        )
        return .init(
            admission: admission,
            materialIdentifier: materialIdentifier,
            session: session
        )
    }

    @discardableResult
    private func admitManifest(to harness: inout Harness) throws
        -> [Session.Effect] {
        let run = try Fixture.aggregateRun(
            canonicalBytes: harness.admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: harness.admission
        )
        return admit(run, to: &harness.session)
    }

    private func driveToTranscript(
        harness: inout Harness,
        evaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
    ) throws -> PreparedTranscript {
        let prepared = try driveToGroupedCommitment(
            harness: &harness,
            evaluator: evaluator
        )
        let preparation = prepared.preparation
        let conductorSequence = prepared.nextConductorSequence

        let commitmentRun = try Fixture.aggregateRun(
            canonicalBytes: preparation.commitmentSet.canonicalBytes,
            kind: .commitmentSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: conductorSequence,
            harness: harness.admission
        )
        _ = admit(commitmentRun, to: &harness.session)
        #expect(
            harness.session.state == .active(.anonymousComponentSubmission)
        )
        let componentRun = try Fixture.aggregateRun(
            canonicalBytes: preparation.componentSet.canonicalBytes,
            kind: .componentSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .anonymousComponentSubmission,
            sequence: commitmentRun.nextSequence,
            harness: harness.admission
        )
        let componentEffects = admit(componentRun, to: &harness.session)
        let transcript = try #require(
            componentEffects.compactMap {
                effect -> OpalFusion.Mosaic.OpalV0
                    .UnsignedTransactionTranscript? in
                guard case let .admission(
                    .componentSetAdmitted(_, transcript)
                ) = effect else {
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

    private func driveToGroupedCommitment(
        harness: inout Harness,
        evaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
    ) throws -> PreparedGroupedCommitment {
        let manifestRun = try Fixture.aggregateRun(
            canonicalBytes: harness.admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: harness.admission
        )
        _ = admit(manifestRun, to: &harness.session)

        let materialized = try MosaicMainnetAlphaFixtures
            .makeMaterializedPreparation(
                election: harness.admission.election,
                manifest: harness.admission.manifest,
                attemptIdentifier: harness.admission.attemptIdentifier,
                generationIdentifier: harness.admission.generationIdentifier,
                localContributor: harness.admission.localControlIdentity,
                localMaterialIdentifier: harness.materialIdentifier
            )
        let preparation = materialized.prepared
        let localContributionMaterial = try #require(
            materialized.materials[harness.admission.localControlIdentity]
        )
        let material = try makeLocalAuthorizationMaterial(
            material: localContributionMaterial,
            evaluator: evaluator
        )
        let localCommitRun = try Fixture.aggregateRun(
            canonicalBytes: material.playerCommit.canonicalBytes,
            kind: .playerCommit,
            sender: harness.admission.localControlIdentity,
            phase: .walletReservation,
            sequence: 0,
            harness: harness.admission
        )
        _ = admit(localCommitRun, to: &harness.session)

        var conductorSequence = manifestRun.nextSequence
        let playerCommits = try harness.admission.manifest.core
            .orderedContributors.map {
            try #require(materialized.materials[$0]?.playerCommit)
        }
        for (index, playerCommit) in playerCommits.enumerated() {
            let responseSet = playerCommit.contributor
                == harness.admission.localControlIdentity
                ? material.responseSet
                : try Fixture.makeAuthorizationResponseSet(
                    playerCommit: playerCommit,
                    byteSeed: UInt8(index + 1)
                )
            let run = try Fixture.aggregateRun(
                canonicalBytes: responseSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: harness.admission.election.result.roster.conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                harness: harness.admission
            )
            _ = admit(run, to: &harness.session)
            conductorSequence = run.nextSequence
        }
        _ = harness.session.apply(
            input: .authorizationResponseSetValidated(
                .init(validation: material.validation)
            )
        )
        #expect(harness.session.state == .active(.walletReservation))
        let publicationRequest = try reservationPublicationRequest(
            harness: harness,
            playerCommit: material.playerCommit
        )
        let publicationValidation = try Session.ReservationPublicationValidation(
            validating: publicationRequest,
            using: ReservationReferenceValidator(
                expectedReference: publicationRequest.reservationReference
            )
        )
        #expect(
            harness.session.apply(
                input: .reservationPublicationValidated(
                    publicationValidation
                )
            ).contains {
                guard case .reservationPublicationAccepted = $0 else {
                    return false
                }
                return true
            }
        )
        #expect(harness.session.state == .active(.groupedCommitment))
        #expect(
            harness.session.apply(
                input: .reservationPublicationValidated(
                    publicationValidation
                )
            ) == [.exactDuplicateIgnored]
        )
        return .init(
            preparation: preparation,
            localPlayerCommit: material.playerCommit,
            nextConductorSequence: conductorSequence
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
        #expect(
            componentVerificationKey
                == material.manifest.core
                    .componentAuthorizationVerificationKey
        )
        #expect(
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
            roundIdentifier: material.playerCommit.roundIdentifier,
            contributor: material.playerCommit.contributor,
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

    private func localPlayerCommit(
        harness: Harness,
        commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
    ) throws -> Alpha.PlayerCommit {
        try #require(
            Fixture.makePlayerCommits(
                harness: harness.admission,
                commitmentSet: commitmentSet
            ).first {
                $0.contributor == harness.admission.localControlIdentity
            }
        )
    }

    private func reservationPublicationRequest(
        harness: Harness,
        playerCommit: Alpha.PlayerCommit,
        attemptIdentifier: Session.AttemptIdentifier? = nil,
        generationIdentifier: Session.GenerationIdentifier? = nil,
        materialIdentifier: Session.MaterialIdentifier? = nil,
        contributor: Session.ControlIdentity? = nil,
        manifest: Alpha.RoundManifest? = nil,
        reservationReference: OpalFusion.Host.MosaicReservationReference? = nil
    ) throws -> Session.ReservationPublicationRequest {
        let reference = reservationReference ?? self.reservationReference()
        return .init(
            attemptIdentifier:
                attemptIdentifier ?? harness.admission.attemptIdentifier,
            generationIdentifier:
                generationIdentifier
                    ?? harness.admission.generationIdentifier,
            materialIdentifier:
                materialIdentifier ?? harness.materialIdentifier,
            contributor:
                contributor ?? harness.admission.localControlIdentity,
            manifest: manifest ?? harness.admission.manifest,
            reservationLease: try reservationLease(reference: reference),
            playerCommit: playerCommit
        )
    }

    private func reservationLease(
        reference: OpalFusion.Host.MosaicReservationReference
    ) throws -> OpalFusion.Host.MosaicReservationLease {
        try .init(
            reference: reference,
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: [UInt8](
                            repeating: 0x31,
                            count: 32
                        ),
                        outpointIndex: 0,
                        amountSatoshis: 100_000,
                        lockingScriptBytes: [0x51]
                    ),
                ],
                outputs: [
                    .init(
                        lockingScriptBytes: [0x51],
                        amountSatoshis: 99_000
                    ),
                ]
            )
        )
    }

    private func reservationReference(
        finalByte: UInt8 = 0xC1,
        generation: UInt64 = 1
    ) -> OpalFusion.Host.MosaicReservationReference {
        .init(
            identifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, finalByte
                )
            ),
            generation: generation
        )
    }

    private func conflictingPlayerCommit(
        with playerCommit: Alpha.PlayerCommit
    ) throws -> Alpha.PlayerCommit {
        var requests = playerCommit.componentAuthorizationRequests
        var rawMessage = requests[0].blindedMessage.rawRepresentation
        rawMessage[rawMessage.startIndex] ^= 0x01
        requests[0] = try .init(
            slot: 0,
            blindedMessage: .init(rawRepresentation: rawMessage)
        )
        return try .init(
            roundIdentifier: playerCommit.roundIdentifier,
            contributor: playerCommit.contributor,
            groupedCommitment: playerCommit.groupedCommitment,
            componentAuthorizationRequests: requests,
            bchSignatureAuthorizationRequests:
                playerCommit.bchSignatureAuthorizationRequests
        )
    }

    private func expectReservationFailure(
        _ effects: [Session.Effect],
        harness: Harness,
        during phase: Attempt.Phase,
        failure: Session.Failure
    ) {
        #expect(
            effects.suffix(3) == [
                .localAttempt(
                    .walletReservationReleaseRequired(
                        contributor: harness.admission.localControlIdentity,
                        materialIdentifier: harness.materialIdentifier
                    )
                ),
                .localAttempt(
                    .attemptTerminated(
                        .failed(
                            .aborted(
                                during: phase,
                                reason: .invalidAuthenticatedMessage
                            )
                        )
                    )
                ),
                .sessionTerminated(.failed(failure)),
            ]
        )
        #expect(
            harness.session.admissionLedgerState
                == .terminal(.failed(.runtimeSessionBridgeMismatch))
        )
    }

    private func admit(
        _ run: Fixture.AggregateRun,
        to session: inout Session
    ) -> [Session.Effect] {
        var effects = session.apply(input: .control(run.reservation))
        for fragment in run.fragments {
            effects.append(
                contentsOf: session.apply(input: .control(fragment))
            )
        }
        return effects
    }
}
