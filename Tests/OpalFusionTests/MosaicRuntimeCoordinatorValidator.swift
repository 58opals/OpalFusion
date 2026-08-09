// MosaicRuntimeCoordinatorValidator.swift

import Foundation
import Testing
@testable import OpalFusion

@Suite("Mosaic ordered runtime coordinator validation")
struct MosaicRuntimeCoordinatorValidator {
    typealias Coordinator = OpalFusion.Mosaic.RuntimeCoordinator
    typealias RuntimeSession = OpalFusion.Mosaic.RuntimeSession

    @Test(
        "Cancellation waits for an in-flight reservation and releases the late lease",
        .timeLimit(.minutes(1))
    )
    func releaseLateReservationAfterCancellation() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(reserveSuspension: suspension)

        await harness.coordinator.start()
        await harness.source.waitUntilOpened()
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeManifestMessage(
                    fixture: harness.fixture
                )
            )
        )
        await suspension.waitUntilSuspended()

        await harness.coordinator.stop()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(
                    .cancelled(
                        .requested(during: .walletReservation),
                        inputSource: nil
                    )
                )
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(
            await harness.signals.count(.reservationPublished) == 0
        )
        #expect(
            await harness.coordinator.reservationLifecycle
                == .released(harness.lease.reference)
        )
    }

    @Test(
        "Source loss during reservation releases the late lease without publication",
        .timeLimit(.minutes(1))
    )
    func releaseLateReservationAfterSourceLoss() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(reserveSuspension: suspension)

        await harness.coordinator.start()
        await harness.source.waitUntilOpened()
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeManifestMessage(
                    fixture: harness.fixture
                )
            )
        )
        await suspension.waitUntilSuspended()

        await harness.source.finish()
        await harness.source.waitUntilClosed()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(
                    .cancelled(
                        .requested(during: .walletReservation),
                        inputSource: .finished
                    )
                )
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(
            await harness.signals.count(.reservationPublished) == 0
        )
    }

    @Test(
        "A claimed reservation publication finishes before a later release",
        .timeLimit(.minutes(1))
    )
    func finishClaimedPublicationBeforeRelease() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(
            reservationPublicationSuspension: suspension
        )

        await harness.coordinator.start()
        await harness.source.waitUntilOpened()
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeManifestMessage(
                    fixture: harness.fixture
                )
            )
        )
        await suspension.waitUntilSuspended()

        await harness.source.finish()
        await harness.source.waitUntilClosed()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.signals.count(.reservationPublished) == 1
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(
            await harness.coordinator.state
                == .terminal(
                    .cancelled(
                        .requested(during: .walletReservation),
                        inputSource: .finished
                    )
                )
        )
    }

    @Test(
        "Input-source completion drains release before exposing cancellation",
        .timeLimit(.minutes(1))
    )
    func drainReleaseBeforeSourceCancellation() async throws {
        let harness = try makeHarness()

        await harness.coordinator.start()
        await harness.source.waitUntilOpened()
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeManifestMessage(
                    fixture: harness.fixture
                )
            )
        )
        await harness.signals.wait(for: .reservationPublished)
        await harness.source.finish()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(
                    .cancelled(
                        .requested(during: .walletReservation),
                        inputSource: .finished
                    )
                )
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(await harness.source.closeCount == 1)
    }

    @Test(
        "A pre-sign publication failure releases before terminal failure",
        .timeLimit(.minutes(1))
    )
    func releaseAfterPreSignPublicationFailure() async throws {
        let harness = try makeHarness()
        await harness.signals.fail(.preSignPublished)

        try await sendThroughComponentSet(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.preSignPublicationFailed))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(await harness.host.signingRequests.isEmpty)
    }

    @Test(
        "Cancellation after signing may begin requires recovery and never releases",
        .timeLimit(.minutes(1))
    )
    func requireRecoveryAfterSigningStarts() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(signingSuspension: suspension)

        try await sendThroughTranscriptAgreement(harness)
        await suspension.waitUntilSuspended()
        await harness.coordinator.stop()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .recoveryRequired(
                    .init(
                        reservationReference: harness.lease.reference,
                        reason: .cancellationAfterSigningMayHaveStarted
                    )
                )
        )
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(
            await harness.signals.count(.localSignaturesPublished) == 0
        )
    }

    @Test(
        "A release that wins before the signing claim prevents host signing",
        .timeLimit(.minutes(1))
    )
    func releaseBeforeSigningClaim() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(
            signingRequestSuspension: suspension
        )

        try await sendThroughTranscriptAgreement(harness)
        await suspension.waitUntilSuspended()
        await harness.source.finish()
        await harness.source.waitUntilClosed()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(await harness.host.signingRequests.isEmpty)
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(
            await harness.coordinator.state
                == .terminal(
                    .cancelled(
                        .requested(during: .bchSigning),
                        inputSource: .finished
                    )
                )
        )
    }

    @Test(
        "A mismatched local inclusion result terminates and closes the source",
        .timeLimit(.minutes(1))
    )
    func closeSourceAfterTerminalLocalSubmission() async throws {
        let harness = try makeHarness(invalidInclusionMaterial: true)

        try await sendThroughComponentSet(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(
                    .failed(.runtime(.invalidTranscriptInclusionValidation))
                )
        )
        #expect(await harness.source.closeCount == 1)
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(
            await harness.signals.count(.preSignPublished) == 0
        )
    }

    @Test(
        "Exact complete transaction commits before successful termination",
        .timeLimit(.minutes(1))
    )
    func commitExactCompleteTransactionBeforeCompletion() async throws {
        let harness = try makeHarness()

        try await sendThroughTranscriptAgreement(harness)
        await harness.signals.wait(for: .localSignaturesPublished)
        await harness.source.send(
            .hostResult(
                .signedTransactionValidated(
                    attemptIdentifier: harness.fixture.attemptIdentifier,
                    generationIdentifier: harness.fixture.generationIdentifier,
                    contributorSigners: harness.fixture.roster.contributors
                )
            )
        )
        await harness.coordinator.waitForTermination()

        #expect(await harness.coordinator.state == .terminal(.completed))
        let commits = await harness.host.completeCommits
        #expect(commits.count == 1)
        #expect(commits.first?.0 == harness.lease.reference)
        #expect(commits.first?.1 == harness.completeTransaction)
        #expect(await harness.host.legacyCommitCount == 0)
        #expect(await harness.host.releasedReferences.isEmpty)
    }

    @Test(
        "A complete-transaction commit failure requires recovery",
        .timeLimit(.minutes(1))
    )
    func requireRecoveryAfterCompleteCommitFailure() async throws {
        let harness = try makeHarness()
        await harness.host.failCompleteCommit()

        try await sendThroughTranscriptAgreement(harness)
        await harness.signals.wait(for: .localSignaturesPublished)
        await harness.source.send(
            .hostResult(
                .signedTransactionValidated(
                    attemptIdentifier: harness.fixture.attemptIdentifier,
                    generationIdentifier: harness.fixture.generationIdentifier,
                    contributorSigners: harness.fixture.roster.contributors
                )
            )
        )
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .recoveryRequired(
                    .init(
                        reservationReference: harness.lease.reference,
                        reason: .completeTransactionCommitFailed
                    )
                )
        )
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(await harness.host.legacyCommitCount == 0)
    }

    @Test(
        "A reservation-release failure requires recovery after one attempt",
        .timeLimit(.minutes(1))
    )
    func requireRecoveryAfterReleaseFailure() async throws {
        let harness = try makeHarness()
        await harness.host.failRelease()

        await harness.coordinator.start()
        await harness.source.waitUntilOpened()
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeManifestMessage(
                    fixture: harness.fixture
                )
            )
        )
        await harness.signals.wait(for: .reservationPublished)
        await harness.source.finish()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .recoveryRequired(
                    .init(
                        reservationReference: harness.lease.reference,
                        reason: .reservationReleaseFailed
                    )
                )
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(await harness.host.signingRequests.isEmpty)
        #expect(await harness.host.completeCommits.isEmpty)
    }

    @Test("The coordinator rejects a conductor as a wallet contributor")
    func rejectConductorCoordinator() async throws {
        let fixture = try MosaicRuntimeSessionDriverFixture.makeFixture(
            localRole: .conductor
        )
        let source = MosaicRuntimeSessionDriverInputProbe()
        let signals = MosaicRuntimeCoordinatorSignalProbe()
        let lease = try makeLease()
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: lease,
            finalizedTransaction: .init(signedFusionTransactionBytes: [0x01])
        )
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [0x02]
        )

        #expect(throws: Coordinator.Failure.localPeerIsNotContributor) {
            _ = try Coordinator(
                runtimeSession: fixture.session,
                dependencies: dependencies(
                    fixture: fixture,
                    source: source,
                    signals: signals,
                    host: host,
                    lease: lease,
                    completeTransaction: complete
                )
            )
        }
    }

    private struct Harness: Sendable {
        let fixture: MosaicRuntimeSessionFixture
        let source: MosaicRuntimeSessionDriverInputProbe
        let signals: MosaicRuntimeCoordinatorSignalProbe
        let host: MosaicRuntimeCoordinatorHostProbe
        let lease: OpalFusion.Host.MosaicReservationLease
        let completeTransaction: OpalFusion.Host.MosaicCompleteTransaction
        let coordinator: Coordinator
    }

    private func makeHarness(
        reserveSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        reservationPublicationSuspension:
            MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        signingRequestSuspension:
            MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        signingSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        invalidInclusionMaterial: Bool = false
    ) throws -> Harness {
        let fixture = try MosaicRuntimeSessionDriverFixture.makeFixture()
        let source = MosaicRuntimeSessionDriverInputProbe()
        let signals = MosaicRuntimeCoordinatorSignalProbe()
        let lease = try makeLease()
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: lease,
            finalizedTransaction: .init(
                signedFusionTransactionBytes: [0x01, 0x02]
            ),
            reserveSuspension: reserveSuspension,
            signingSuspension: signingSuspension
        )
        let completeTransaction = try OpalFusion.Host
            .MosaicCompleteTransaction(transactionBytes: [0x03, 0x04])
        let coordinator = try Coordinator(
            runtimeSession: fixture.session,
            dependencies: dependencies(
                fixture: fixture,
                source: source,
                signals: signals,
                host: host,
                lease: lease,
                completeTransaction: completeTransaction,
                reservationPublicationSuspension:
                    reservationPublicationSuspension,
                signingRequestSuspension: signingRequestSuspension,
                invalidInclusionMaterial: invalidInclusionMaterial
            )
        )
        return .init(
            fixture: fixture,
            source: source,
            signals: signals,
            host: host,
            lease: lease,
            completeTransaction: completeTransaction,
            coordinator: coordinator
        )
    }

    private func dependencies(
        fixture: MosaicRuntimeSessionFixture,
        source: MosaicRuntimeSessionDriverInputProbe,
        signals: MosaicRuntimeCoordinatorSignalProbe,
        host: MosaicRuntimeCoordinatorHostProbe,
        lease: OpalFusion.Host.MosaicReservationLease,
        completeTransaction: OpalFusion.Host.MosaicCompleteTransaction,
        reservationPublicationSuspension:
            MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        signingRequestSuspension:
            MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        invalidInclusionMaterial: Bool = false
    ) -> Coordinator.Dependencies {
        .init(
            transactionHost: host,
            openInputStream: {
                await source.open()
            },
            closeInputSource: {
                await source.close()
            },
            makeReservationRequest: { eligibility in
                try .init(
                    attemptIdentifier: eligibility.context.attemptIdentifier
                        .validatedBytes,
                    networkGenesisHash: eligibility.context.profile
                        .networkGenesisHash!,
                    roundIdentifier: eligibility.manifest.roundIdentifier,
                    expiresAt: lease.expiresAt,
                    componentCount: OpalFusion.Mosaic.OpalV0
                        .componentAuthorizationCountPerContributor,
                    feeRateSatoshisPerByte: 1,
                    minimumExcessFeeSatoshis: 0,
                    maximumExcessFeeSatoshis: 0,
                    transactionProfileIdentifier: eligibility.context.profile
                        .transactionProfileIdentifier
                )
            },
            publishReservedContribution: { _, _ in
                await reservationPublicationSuspension?.suspendIfArmed()
                try await signals.record(.reservationPublished)
            },
            validateTranscriptInclusion: { request in
                try MosaicUnsignedTransactionTranscriptFixtures
                    .makeTranscriptInclusionValidation(
                        attemptIdentifier: request.context.attemptIdentifier,
                        generationIdentifier: request.context
                            .generationIdentifier,
                        contributor: request.context.contributor,
                        materialIdentifier: invalidInclusionMaterial
                            ? .init(opaqueBytes: [0xFF])
                            : request.context.materialIdentifier,
                        transcript: request.transcript
                    )
            },
            publishPreSignAcknowledgement: { _ in
                try await signals.record(.preSignPublished)
            },
            makeSigningRequest: { eligibility, reservedLease in
                await signingRequestSuspension?.suspendIfArmed()
                let spentInputs = eligibility.transcript.componentSet.components
                    .compactMap { component -> OpalFusion.Host.ParticipantInput? in
                        guard case let .input(input) = component.payload else {
                            return nil
                        }
                        return .init(
                            outpointTransactionHashBytes:
                                input.previousTransactionHash,
                            outpointIndex: input.outputIndex,
                            amountSatoshis: input.amountSatoshis,
                            lockingScriptBytes: [0x51]
                        )
                    }
                    .sorted { lhs, rhs in
                        if lhs.outpointTransactionHashBytes
                            != rhs.outpointTransactionHashBytes {
                            return lhs.outpointTransactionHashBytes
                                .lexicographicallyPrecedes(
                                    rhs.outpointTransactionHashBytes
                                )
                        }
                        return lhs.outpointIndex < rhs.outpointIndex
                    }
                return try .init(
                    reservationReference: reservedLease.reference,
                    roundIdentifier: eligibility.transcript.manifest
                        .roundIdentifier,
                    transcriptBinding: eligibility.transcript
                        .transcriptBinding,
                    unsignedTransactionBytes: eligibility.transcript
                        .unsignedTransactionBytes,
                    spentInputs: spentInputs,
                    localInputIndices: [0],
                    expectedLocalOutputs: reservedLease
                        .participantReservation.outputs,
                    feeRateSatoshisPerByte: 1,
                    minimumExcessFeeSatoshis: 0,
                    maximumExcessFeeSatoshis: 0,
                    transactionProfileIdentifier: eligibility.context.profile
                        .transactionProfileIdentifier
                )
            },
            validateAndPublishLocalSignatures: { _, _, _ in
                try await signals.record(.localSignaturesPublished)
            },
            loadValidatedCompleteTransaction: { _, receivedLease in
                guard receivedLease == lease else {
                    throw ProbeError.leaseMismatch
                }
                return completeTransaction
            }
        )
    }

    private func sendThroughComponentSet(
        _ harness: Harness
    ) async throws {
        await harness.coordinator.start()
        await harness.source.waitUntilOpened()
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeManifestMessage(
                    fixture: harness.fixture
                )
            )
        )
        await harness.signals.wait(for: .reservationPublished)
        await harness.source.send(
            .hostResult(
                .walletReservationsPrepared(
                    attemptIdentifier: harness.fixture.attemptIdentifier,
                    generationIdentifier: harness.fixture.generationIdentifier,
                    contributors: harness.fixture.roster.contributors
                )
            )
        )
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeMessage(
                    fixture: harness.fixture,
                    sequence: 1,
                    phase: .groupedCommitment,
                    identifierByte: 0xF1,
                    fact: .groupedCommitmentSet(
                        harness.fixture.transactionPreparation.commitmentSet
                    )
                )
            )
        )
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeMessage(
                    fixture: harness.fixture,
                    sequence: 2,
                    phase: .anonymousComponentSubmission,
                    identifierByte: 0xF2,
                    fact: .anonymousComponentSet(
                        harness.fixture.transactionPreparation.componentSet
                    )
                )
            )
        )
    }

    private func sendThroughTranscriptAgreement(
        _ harness: Harness
    ) async throws {
        try await sendThroughComponentSet(harness)
        await harness.signals.wait(for: .preSignPublished)
        await harness.source.send(
            .authenticated(
                try MosaicRuntimeSessionDriverFixture.makeMessage(
                    fixture: harness.fixture,
                    sequence: 3,
                    phase: .transcriptAgreement,
                    identifierByte: 0xF3,
                    fact: .transcriptAcknowledgementSet(
                        MosaicManifestSignatureFixtures
                            .transcriptAcknowledgements(
                                for: harness.fixture.roster.contributors,
                                binding: harness.fixture.manifest,
                                transcriptRoot: harness.fixture
                                    .transactionPreparation.transcript
                                    .transcriptRoot
                            )
                    )
                )
            )
        )
    }

    private func makeLease() throws -> OpalFusion.Host.MosaicReservationLease {
        let reference = OpalFusion.Host.MosaicReservationReference(
            identifier: try #require(
                UUID(uuidString: "00000000-0000-0000-0000-0000000000C1")
            ),
            generation: 1
        )
        return try .init(
            reference: reference,
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: Array(
                            repeating: 0x31,
                            count: 32
                        ),
                        outpointIndex: 0,
                        amountSatoshis: 100_000,
                        lockingScriptBytes: [0x51]
                    )
                ],
                outputs: [
                    .init(lockingScriptBytes: [0x51], amountSatoshis: 99_000)
                ]
            )
        )
    }

    private enum ProbeError: Error {
        case leaseMismatch
    }
}
