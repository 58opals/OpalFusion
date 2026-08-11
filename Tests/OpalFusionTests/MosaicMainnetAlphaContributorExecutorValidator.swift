// MosaicMainnetAlphaContributorExecutorValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha contributor executor")
struct MosaicMainnetAlphaContributorExecutorValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Coordinator = Alpha.ReservationCoordinator
    typealias ExecutionFixture = MosaicMainnetAlphaExecutionFixtures
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures

    init() throws {
        try MosaicMainnetAlphaFixtures.requireAuthorizationEvaluators()
    }

    private actor PublicationProbe {
        enum Signal: CaseIterable, Hashable, Sendable {
            case playerCommitPublished
            case anonymousComponentsPublished
            case preSignPublished
            case localSignaturesPublished
        }

        private var counts: [Signal: Int] = [:]
        private let signalStreams: [Signal: AsyncStream<Void>]
        private let signalContinuations: [Signal: AsyncStream<Void>.Continuation]
        private(set) var playerCommit: Alpha.PlayerCommit?
        private(set) var anonymousComponents:
            [Coordinator.AnonymousComponentPublicationValidation.Entry] = []
        private(set) var anonymousComponentContext:
            Coordinator.AnonymousPublicationContext?
        private(set) var anonymousComponentMaterialBinding:
            Coordinator.AnonymousMaterialBinding?
        private(set) var preSignPublication: (
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            roundIdentifier: [UInt8],
            transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
        )?
        private(set) var localSignatures:
            [Coordinator.AnonymousBCHSignaturePublicationValidation.Entry] = []
        private(set) var localSignatureContext:
            Coordinator.AnonymousPublicationContext?
        private(set) var localSignatureMaterialBinding:
            Coordinator.AnonymousMaterialBinding?

        init() {
            var streams: [Signal: AsyncStream<Void>] = [:]
            var continuations: [Signal: AsyncStream<Void>.Continuation] = [:]
            for signal in Signal.allCases {
                let (stream, continuation) = AsyncStream<Void>.makeStream(
                    bufferingPolicy: .bufferingNewest(1)
                )
                streams[signal] = stream
                continuations[signal] = continuation
            }
            signalStreams = streams
            signalContinuations = continuations
        }

        func publish(_ playerCommit: Alpha.PlayerCommit) {
            self.playerCommit = playerCommit
            record(.playerCommitPublished)
        }

        func publishAnonymousComponents(
            _ validation: Coordinator
                .AnonymousComponentPublicationValidation
        ) {
            anonymousComponentContext = validation.context
            anonymousComponentMaterialBinding = validation.materialBinding
            anonymousComponents = validation.entries
            record(.anonymousComponentsPublished)
        }

        func publishPreSign(
            contributor: OpalFusion.Mosaic.Attempt.ControlIdentity,
            roundIdentifier: [UInt8],
            transcriptRoot: OpalFusion.Mosaic.Attempt.TranscriptRoot
        ) {
            preSignPublication = (
                contributor,
                roundIdentifier,
                transcriptRoot
            )
            record(.preSignPublished)
        }

        func publishLocalSignatures(
            _ validation: Coordinator
                .AnonymousBCHSignaturePublicationValidation
        ) {
            localSignatureContext = validation.context
            localSignatureMaterialBinding = validation.materialBinding
            localSignatures = validation.entries
            record(.localSignaturesPublished)
        }

        func wait(for signal: Signal) async {
            guard counts[signal, default: 0] == 0 else {
                return
            }
            guard let stream = signalStreams[signal] else {
                return
            }
            for await _ in stream {
                return
            }
        }

        func count(_ signal: Signal) -> Int {
            counts[signal, default: 0]
        }

        private func record(_ signal: Signal) {
            counts[signal, default: 0] += 1
            signalContinuations[signal]?.yield()
        }
    }

    private final class GroupedCommitmentProbe: Sendable {
        private let stream: AsyncStream<Void>
        private let continuation: AsyncStream<Void>.Continuation

        init() {
            (stream, continuation) = AsyncStream<Void>.makeStream(
                bufferingPolicy: .bufferingNewest(1)
            )
        }

        func observe(_ effect: Alpha.RuntimeSession.Effect) {
            guard case .admission(
                .phaseAdvanced(.groupedCommitment)
            ) = effect else {
                return
            }
            continuation.yield()
        }

        func wait() async {
            for await _ in stream {
                return
            }
        }
    }

    private struct Harness {
        let prepared: ExecutionFixture.Prepared
        let host: MosaicRuntimeCoordinatorHostProbe
        let probe: PublicationProbe
        let groupedCommitmentProbe: GroupedCommitmentProbe
        let coordinator: Coordinator
    }

    private struct RejectingPreviousOutputSource:
        OpalFusion.Host.MosaicPreviousOutputSource
    {
        func resolvePreviousOutputs(
            for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            throw ProbeFailure.previousOutputResolution
        }
    }

    @Test(
        "Execute six contributors through exact local host commit",
        .timeLimit(.minutes(3))
    )
    func executeThroughExactCommit() async throws {
        let commitSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await commitSuspension.arm()
        let harness = try await makeHarness(
            completeCommitSuspension: commitSuspension
        )
        await harness.coordinator.start()
        let nextSequence = try await driveThroughLocalSigning(harness)
        try await submitCompletionDocuments(
            harness,
            conductorSequence: nextSequence
        )
        await commitSuspension.waitUntilSuspended()
        #expect(await harness.coordinator.inputSourceDidTerminate(.finished))
        await harness.coordinator.stop()
        await commitSuspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(await harness.coordinator.state == .terminal(.completed))
        #expect(
            await harness.coordinator.reservationLifecycle
                == .committed(harness.prepared.localMaterial.reservationLease.reference)
        )
        #expect(await harness.host.reservationRequests.count == 1)
        #expect(
            await harness.host.signingRequests == [harness.prepared.signingRequest]
        )
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(await harness.host.legacyCommitCount == 0)
        let commits = await harness.host.completeCommits
        let commit = try #require(commits.first)
        #expect(commits.count == 1)
        #expect(commit.0 == harness.prepared.localMaterial.reservationLease.reference)
        #expect(
            commit.1.transactionBytes
                == harness.prepared.completePayload.completeTransaction
                    .transactionBytes
        )
        #expect(
            await harness.probe.playerCommit
                == harness.prepared.localMaterial.playerCommit
        )
        let expectedAnonymousContext = try Coordinator
            .AnonymousPublicationContext(
                validating: harness.prepared.localMaterial,
                against: harness.prepared.session.context
            )
        let expectedMaterialBinding = Coordinator.AnonymousMaterialBinding(
            material: harness.prepared.localMaterial
        )
        #expect(
            await harness.probe.anonymousComponentContext
                == expectedAnonymousContext
        )
        #expect(
            await harness.probe.anonymousComponentMaterialBinding
                == expectedMaterialBinding
        )
        let anonymousComponents = await harness.probe.anonymousComponents
        #expect(anonymousComponents.count == Alpha.componentCountPerContributor)
        for publication in anonymousComponents {
            let slot = harness.prepared.localMaterial.slots[publication.slot]
            #expect(publication.recipientEventIdentity == slot.recipientEventIdentity)
            #expect(publication.payload.component == slot.component)
            #expect(
                publication.payload.authorizationToken
                    == harness.prepared.localAuthorizationValidation
                        .componentAuthorizationTokens[publication.slot]
            )
        }
        let preSign = try #require(await harness.probe.preSignPublication)
        #expect(
            preSign.contributor
                == harness.prepared.admission.localControlIdentity
        )
        #expect(
            preSign.roundIdentifier
                == harness.prepared.admission.manifest.core.roundIdentifier
        )
        #expect(
            preSign.transcriptRoot
                == harness.prepared.materialized.prepared.transcript.transcriptRoot
        )
        let localSignatures = await harness.probe.localSignatures
        #expect(localSignatures.count == 1)
        #expect(
            await harness.probe.localSignatureContext
                == expectedAnonymousContext
        )
        #expect(
            await harness.probe.localSignatureMaterialBinding
                == expectedMaterialBinding
        )
        let localInputIndex = try #require(
            harness.prepared.signingRequest.localInputIndices.first
        )
        #expect(
            localSignatures.first?.submission.entry
                == harness.prepared.signatureSet.entries[localInputIndex]
        )
    }

    @Test(
        "Cancellation after the host signing boundary requires recovery",
        .timeLimit(.minutes(3))
    )
    func requireRecoveryAfterSigningCancellation() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try await makeHarness(signingSuspension: suspension)
        await harness.coordinator.start()
        _ = try await driveToBCHSigning(harness)
        await suspension.waitUntilSuspended()

        await harness.coordinator.stop()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state == .recoveryRequired(
                .init(
                    reservationReference:
                        harness.prepared.localMaterial.reservationLease.reference,
                    reason: .signingMayHaveStarted
                )
            )
        )
        #expect(await harness.host.signingRequests.count == 1)
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(await harness.host.completeCommits.isEmpty)
        #expect(
            await harness.probe.count(.localSignaturesPublished) == 0
        )
    }

    @Test(
        "An exact commit failure requires recovery without release",
        .timeLimit(.minutes(3))
    )
    func requireRecoveryAfterCommitFailure() async throws {
        let harness = try await makeHarness()
        await harness.host.failCompleteCommit()
        await harness.coordinator.start()
        let nextSequence = try await driveThroughLocalSigning(harness)
        try await submitCompletionDocuments(
            harness,
            conductorSequence: nextSequence
        )
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state == .recoveryRequired(
                .init(
                    reservationReference:
                        harness.prepared.localMaterial.reservationLease.reference,
                    reason: .completeTransactionCommitFailed
                )
            )
        )
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(await harness.host.completeCommits.isEmpty)
        #expect(await harness.host.legacyCommitCount == 0)
    }

    @Test(
        "Cancellation during material construction releases without publication",
        .timeLimit(.minutes(3))
    )
    func cancelDuringMaterialConstruction() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try await makeHarness(materialSuspension: suspension)
        await harness.coordinator.start()
        _ = try await submitManifest(to: harness)
        await suspension.waitUntilSuspended()

        await harness.coordinator.stop()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.cancelled(during: .walletReservation))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.prepared.localMaterial.reservationLease.reference]
        )
        #expect(await harness.probe.count(.playerCommitPublished) == 0)
        #expect(await harness.probe.count(.anonymousComponentsPublished) == 0)
    }

    @Test(
        "Cancellation before commitment admission publishes no components",
        .timeLimit(.minutes(3))
    )
    func cancelBeforeCommitmentAdmission() async throws {
        let harness = try await makeHarness()
        await harness.coordinator.start()
        _ = try await driveThroughAuthorizationResponses(harness)
        await harness.groupedCommitmentProbe.wait()
        #expect(await harness.probe.count(.anonymousComponentsPublished) == 0)

        await harness.coordinator.stop()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.cancelled(during: .groupedCommitment))
        )
        #expect(await harness.probe.count(.anonymousComponentsPublished) == 0)
        #expect(
            await harness.host.releasedReferences
                == [harness.prepared.localMaterial.reservationLease.reference]
        )
    }

    @Test(
        "Distinguish pre-sign release from post-sign recovery failures",
        .timeLimit(.minutes(5))
    )
    func distinguishReleaseAndRecoveryFailures() async throws {
        let prepared = try await ExecutionFixture.prepare()

        let commitmentFailure = try makeHarness(prepared: prepared)
        await commitmentFailure.coordinator.start()
        let commitmentSequence = try await driveThroughAuthorizationResponses(
            commitmentFailure
        )
        await commitmentFailure.groupedCommitmentProbe.wait()
        let substitutedCommitmentSet = try makeCommitmentSetMissingLocalMember(
            prepared
        )
        let substitutedCommitmentRun = try Fixture.aggregateRun(
            canonicalBytes: substitutedCommitmentSet.canonicalBytes,
            kind: .commitmentSet,
            sender: prepared.admission.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: commitmentSequence,
            harness: prepared.admission
        )
        try await submit(
            substitutedCommitmentRun,
            to: commitmentFailure.coordinator
        )
        await commitmentFailure.coordinator.waitForTermination()
        #expect(
            await commitmentFailure.coordinator.state
                == .terminal(.failed(.commitmentInclusionValidationFailed))
        )
        #expect(
            await commitmentFailure.probe.count(
                .anonymousComponentsPublished
            ) == 0
        )
        #expect(
            await commitmentFailure.host.releasedReferences
                == [prepared.localMaterial.reservationLease.reference]
        )
        #expect(await commitmentFailure.host.signingRequests.isEmpty)
        #expect(await commitmentFailure.host.completeCommits.isEmpty)

        let resolutionFailure = try makeHarness(
            prepared: prepared,
            failPreviousOutputResolution: true
        )
        await resolutionFailure.coordinator.start()
        _ = try await driveToBCHSigning(resolutionFailure)
        await resolutionFailure.coordinator.waitForTermination()
        #expect(
            await resolutionFailure.coordinator.state
                == .terminal(.failed(.previousOutputResolutionFailed))
        )
        #expect(
            await resolutionFailure.host.releasedReferences
                == [prepared.localMaterial.reservationLease.reference]
        )
        #expect(await resolutionFailure.host.signingRequests.isEmpty)
        #expect(await resolutionFailure.host.completeCommits.isEmpty)

        let publicationFailure = try makeHarness(
            prepared: prepared,
            failLocalSignaturePublication: true
        )
        await publicationFailure.coordinator.start()
        _ = try await driveToBCHSigning(publicationFailure)
        await publicationFailure.coordinator.waitForTermination()
        #expect(
            await publicationFailure.coordinator.state
                == .recoveryRequired(
                    .init(
                        reservationReference:
                            prepared.localMaterial.reservationLease.reference,
                        reason: .localBCHSignaturePublicationFailed
                    )
                )
        )
        #expect(await publicationFailure.host.releasedReferences.isEmpty)
        #expect(await publicationFailure.host.signingRequests.count == 1)
        #expect(await publicationFailure.host.completeCommits.isEmpty)

        let validationFailure = try makeHarness(prepared: prepared)
        await validationFailure.coordinator.start()
        let nextSequence = try await driveThroughLocalSigning(validationFailure)
        let invalidCompletion = try makeInvalidSignatureCompletion(prepared)
        try await submitCompletionDocuments(
            validationFailure,
            conductorSequence: nextSequence,
            signatureSet: invalidCompletion.signatureSet,
            completePayload: invalidCompletion.payload
        )
        await validationFailure.coordinator.waitForTermination()
        #expect(
            await validationFailure.coordinator.state
                == .recoveryRequired(
                    .init(
                        reservationReference:
                            prepared.localMaterial.reservationLease.reference,
                        reason: .completeTransactionValidationFailed
                    )
                )
        )
        #expect(await validationFailure.host.releasedReferences.isEmpty)
        #expect(await validationFailure.host.completeCommits.isEmpty)
    }

    private func makeHarness(
        signingSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        completeCommitSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        materialSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        failPreviousOutputResolution: Bool = false,
        failLocalSignaturePublication: Bool = false
    ) async throws -> Harness {
        let prepared = try await ExecutionFixture.prepare()
        return try makeHarness(
            prepared: prepared,
            signingSuspension: signingSuspension,
            completeCommitSuspension: completeCommitSuspension,
            materialSuspension: materialSuspension,
            failPreviousOutputResolution: failPreviousOutputResolution,
            failLocalSignaturePublication: failLocalSignaturePublication
        )
    }

    private func makeHarness(
        prepared: ExecutionFixture.Prepared,
        signingSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        completeCommitSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        materialSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        failPreviousOutputResolution: Bool = false,
        failLocalSignaturePublication: Bool = false
    ) throws -> Harness {
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: prepared.localMaterial.reservationLease,
            finalizedTransaction: prepared.localFinalizedTransaction,
            signingSuspension: signingSuspension,
            completeCommitSuspension: completeCommitSuspension
        )
        let probe = PublicationProbe()
        let groupedCommitmentProbe = GroupedCommitmentProbe()
        let lease = prepared.localMaterial.reservationLease
        let previousOutputSource: any OpalFusion.Host
            .MosaicPreviousOutputSource = failPreviousOutputResolution
                ? RejectingPreviousOutputSource()
                : prepared.previousOutputSource
        let coordinator = try Coordinator(
            runtimeSession: prepared.session,
            dependencies: .init(
                execution: .init(
                    transactionHost: host,
                    previousOutputSource: previousOutputSource,
                    makeLocalContributionMaterial: { eligibility, receivedLease in
                        guard eligibility.context == prepared.session.context,
                              eligibility.manifest == prepared.admission.manifest,
                              receivedLease == lease else {
                            throw ProbeFailure.contextMismatch
                        }
                        await materialSuspension?.suspendIfArmed()
                        return prepared.localMaterial
                    },
                    publishPlayerCommit: { validation in
                        await probe.publish(validation.request.playerCommit)
                    },
                    publishAnonymousComponents: { publications in
                        await probe.publishAnonymousComponents(publications)
                    },
                    publishPreSignAcknowledgement: { validation in
                        await probe.publishPreSign(
                            contributor: validation.contributor,
                            roundIdentifier:
                                validation.transcript.manifest.roundIdentifier,
                            transcriptRoot:
                                validation.transcript.transcriptRoot
                        )
                    },
                    publishLocalBCHSignatures: { publications in
                        guard !failLocalSignaturePublication else {
                            throw ProbeFailure.localSignaturePublication
                        }
                        await probe.publishLocalSignatures(publications)
                    }
                ),
                expectedReservationExpiration: lease.expiresAt,
                makeReservationRequest: { eligibility in
                    try ExecutionFixture.reservationRequest(
                        for: eligibility,
                        expiresAt: lease.expiresAt
                    )
                },
                runtimeEffectObserver: { effect in
                    groupedCommitmentProbe.observe(effect)
                }
            )
        )
        return .init(
            prepared: prepared,
            host: host,
            probe: probe,
            groupedCommitmentProbe: groupedCommitmentProbe,
            coordinator: coordinator
        )
    }

    private func driveThroughLocalSigning(
        _ harness: Harness
    ) async throws -> UInt64 {
        let nextSequence = try await driveToBCHSigning(harness)
        await harness.probe.wait(for: .localSignaturesPublished)
        return nextSequence
    }

    private func driveToBCHSigning(
        _ harness: Harness
    ) async throws -> UInt64 {
        let conductorSequence = try await driveThroughAuthorizationResponses(
            harness
        )
        await harness.groupedCommitmentProbe.wait()
        #expect(await harness.probe.count(.anonymousComponentsPublished) == 0)

        let admission = harness.prepared.admission
        let commitmentRun = try Fixture.aggregateRun(
            canonicalBytes: harness.prepared.materialized.prepared.commitmentSet
                .canonicalBytes,
            kind: .commitmentSet,
            sender: admission.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: conductorSequence,
            harness: admission
        )
        try await submit(commitmentRun, to: harness.coordinator)
        await harness.probe.wait(for: .anonymousComponentsPublished)
        let componentRun = try Fixture.aggregateRun(
            canonicalBytes: harness.prepared.materialized.prepared.componentSet
                .canonicalBytes,
            kind: .componentSet,
            sender: admission.election.result.roster.conductor,
            phase: .anonymousComponentSubmission,
            sequence: commitmentRun.nextSequence,
            harness: admission
        )
        try await submit(componentRun, to: harness.coordinator)
        await harness.probe.wait(for: .preSignPublished)

        let acknowledgementRun = try Fixture.aggregateRun(
            canonicalBytes: harness.prepared.acknowledgementSet.canonicalBytes,
            kind: .preSignAcknowledgementSet,
            sender: admission.election.result.roster.conductor,
            phase: .transcriptAgreement,
            sequence: componentRun.nextSequence,
            harness: admission
        )
        try await submit(acknowledgementRun, to: harness.coordinator)
        return acknowledgementRun.nextSequence
    }

    private func driveThroughAuthorizationResponses(
        _ harness: Harness
    ) async throws -> UInt64 {
        let admission = harness.prepared.admission
        let manifestRun = try await submitManifest(to: harness)
        await harness.probe.wait(for: .playerCommitPublished)

        let localCommitRun = try Fixture.aggregateRun(
            canonicalBytes:
                harness.prepared.localMaterial.playerCommit.canonicalBytes,
            kind: .playerCommit,
            sender: admission.localControlIdentity,
            phase: .walletReservation,
            sequence: 0,
            harness: admission
        )
        try await submit(localCommitRun, to: harness.coordinator)

        var conductorSequence = manifestRun.nextSequence
        for (index, contributor) in admission.manifest.core
            .orderedContributors.enumerated() {
            let material = try #require(
                harness.prepared.materialized.materials[contributor]
            )
            let responseSet = contributor == admission.localControlIdentity
                ? harness.prepared.localAuthorizationResponseSet
                : try Fixture.makeAuthorizationResponseSet(
                    playerCommit: material.playerCommit,
                    byteSeed: UInt8(index + 1)
                )
            let responseRun = try Fixture.aggregateRun(
                canonicalBytes: responseSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: admission.election.result.roster.conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                harness: admission
            )
            try await submit(responseRun, to: harness.coordinator)
            conductorSequence = responseRun.nextSequence
        }
        return conductorSequence
    }

    private func submitManifest(
        to harness: Harness
    ) async throws -> Fixture.AggregateRun {
        let admission = harness.prepared.admission
        let manifestRun = try Fixture.aggregateRun(
            canonicalBytes: admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: admission
        )
        try await submit(manifestRun, to: harness.coordinator)
        return manifestRun
    }

    private func submitCompletionDocuments(
        _ harness: Harness,
        conductorSequence: UInt64,
        signatureSet: Alpha.BCHSignatureSet? = nil,
        completePayload: Alpha.CompleteTransactionPayload? = nil
    ) async throws {
        let admission = harness.prepared.admission
        let signatureSet = signatureSet ?? harness.prepared.signatureSet
        let completePayload = completePayload ?? harness.prepared.completePayload
        let signatureRun = try Fixture.aggregateRun(
            canonicalBytes: signatureSet.canonicalBytes,
            kind: .bchSignatureSet,
            sender: admission.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: conductorSequence,
            harness: admission
        )
        try await submit(signatureRun, to: harness.coordinator)
        let completeRun = try Fixture.aggregateRun(
            canonicalBytes: completePayload.canonicalBytes,
            kind: .completeTransaction,
            sender: admission.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: signatureRun.nextSequence,
            harness: admission
        )
        try await submit(completeRun, to: harness.coordinator)
    }

    private func makeInvalidSignatureCompletion(
        _ prepared: ExecutionFixture.Prepared
    ) throws -> (
        signatureSet: Alpha.BCHSignatureSet,
        payload: Alpha.CompleteTransactionPayload
    ) {
        var entries = prepared.signatureSet.entries
        var signature = entries[0].signature
        signature[0] ^= 0x01
        entries[0] = try .init(
            inputIndex: entries[0].inputIndex,
            signature: signature,
            publicKey: entries[0].publicKey
        )
        let signatureSet = try Alpha.BCHSignatureSet(
            roundIdentifier: prepared.signatureSet.roundIdentifier,
            transcriptRoot: prepared.signatureSet.transcriptRoot,
            entries: entries,
            expectedInputCount: entries.count
        )
        var transaction = prepared.materialized.prepared.transcript.transaction
        for entry in entries {
            let unlockingScript = [UInt8(0x41)] + entry.signature
                + [0x41, 0x21] + entry.publicKey
            transaction = try transaction.settingUnlockingScript(
                unlockingScript,
                at: Int(entry.inputIndex)
            )
        }
        let payload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: signatureSet.roundIdentifier,
            transcriptRoot: signatureSet.transcriptRoot,
            completeTransaction: try .init(
                transactionBytes: transaction.serialize()
            )
        )
        return (signatureSet, payload)
    }

    private func makeCommitmentSetMissingLocalMember(
        _ prepared: ExecutionFixture.Prepared
    ) throws -> OpalFusion.Mosaic.OpalV0.CommitmentSet {
        let localCommitment = prepared.localMaterial.slots[0].commitment
        var commitments = prepared.materialized.prepared.commitmentSet
            .commitments
        let index = try #require(
            commitments.firstIndex(of: localCommitment)
        )
        var substitutedDigest = localCommitment.saltedComponentDigest
        substitutedDigest[0] ^= 0x01
        commitments[index] = try .init(
            saltedComponentDigest: substitutedDigest,
            amountCommitment: localCommitment.amountCommitment,
            communicationPublicKey: localCommitment.communicationPublicKey
        )
        return try .init(
            profile: .opalMainnetAlpha,
            commitments: commitments
        )
    }

    private func submit(
        _ run: Fixture.AggregateRun,
        to coordinator: Coordinator
    ) async throws {
        guard await coordinator.submitControl(run.reservation) else {
            throw ProbeFailure.inputRejected
        }
        for fragment in run.fragments {
            guard await coordinator.submitControl(fragment) else {
                throw ProbeFailure.inputRejected
            }
        }
    }

    private enum ProbeFailure: Error {
        case contextMismatch
        case inputRejected
        case localSignaturePublication
        case previousOutputResolution
    }
}
