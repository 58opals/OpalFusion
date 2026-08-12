// MosaicMainnetAlphaConductorCoordinatorValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha conductor coordinator")
struct MosaicMainnetAlphaConductorCoordinatorValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Bridge = Alpha.PostManifestControlPublicationBridge
    typealias Coordinator = Alpha.ConductorCoordinator
    typealias ExecutionFixture = MosaicMainnetAlphaExecutionFixtures
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures

    init() throws {
        try MosaicMainnetAlphaFixtures.requireAuthorizationEvaluators()
    }

    private actor PublicationProbe {
        struct Waiter {
            let kind: Coordinator.PublicationKind
            let count: Int
            let continuation: CheckedContinuation<Void, Never>
        }

        enum ProbeFailure: Error {
            case injected
        }

        private var publications: [Coordinator.Publication] = []
        private var validations: [Coordinator.PublicationValidation] = []
        private var waiters: [UUID: Waiter] = [:]
        private let failingKind: Coordinator.PublicationKind?
        private let suspendingKind: Coordinator.PublicationKind?
        private let suspension: MosaicRuntimeCoordinatorSuspensionProbe?

        init(
            failingKind: Coordinator.PublicationKind? = nil,
            suspendingKind: Coordinator.PublicationKind? = nil,
            suspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
        ) {
            self.failingKind = failingKind
            self.suspendingKind = suspendingKind
            self.suspension = suspension
        }

        func publish(
            _ validation: Coordinator.PublicationValidation
        ) async throws {
            let publication = validation.publication
            if publication.kind == suspendingKind {
                await suspension?.suspendIfArmed()
            }
            guard publication.kind != failingKind else {
                throw ProbeFailure.injected
            }
            validations.append(validation)
            publications.append(publication)
            var completed: [UUID] = []
            for (identifier, waiter) in waiters {
                if count(waiter.kind) >= waiter.count {
                    waiter.continuation.resume()
                    completed.append(identifier)
                }
            }
            for identifier in completed {
                waiters.removeValue(forKey: identifier)
            }
        }

        func wait(
            for kind: Coordinator.PublicationKind,
            count expectedCount: Int = 1
        ) async {
            guard count(kind) < expectedCount else {
                return
            }
            let identifier = UUID()
            await withTaskCancellationHandler {
                await withCheckedContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume()
                        return
                    }
                    waiters[identifier] = .init(
                        kind: kind,
                        count: expectedCount,
                        continuation: continuation
                    )
                }
            } onCancel: {
                Task {
                    await self.cancelWaiter(identifier)
                }
            }
        }

        private func cancelWaiter(_ identifier: UUID) {
            waiters.removeValue(forKey: identifier)?.continuation.resume()
        }

        func count(_ kind: Coordinator.PublicationKind) -> Int {
            publications.reduce(into: 0) { result, publication in
                if publication.kind == kind {
                    result += 1
                }
            }
        }

        func values() -> [Coordinator.Publication] {
            publications
        }

        func validationValues() -> [Coordinator.PublicationValidation] {
            validations
        }
    }

    private struct RejectingPreviousOutputSource:
        OpalFusion.Host.MosaicPreviousOutputSource
    {
        struct Rejection: Error {}

        func resolvePreviousOutputs(
            for _: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            throw Rejection()
        }
    }

    private struct SuspendingPreviousOutputSource:
        OpalFusion.Host.MosaicPreviousOutputSource
    {
        let source: ExecutionFixture.PreviousOutputSource
        let suspension: MosaicRuntimeCoordinatorSuspensionProbe

        func resolvePreviousOutputs(
            for requests: [OpalFusion.Host.MosaicPreviousOutputRequest]
        ) async throws -> [OpalFusion.Host.MosaicPreviousOutput] {
            await suspension.suspendIfArmed()
            return try await source.resolvePreviousOutputs(for: requests)
        }
    }

    private struct Harness {
        let admission: Fixture.Harness
        let materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation
        let completion: ExecutionFixture.Completion
        let coordinator: Coordinator
        let publications: PublicationProbe
    }

    private struct AuthorizationHarness {
        let admission: Fixture.Harness
        let materialized: MosaicMainnetAlphaFixtures.MaterializedPreparation
        let coordinator: Coordinator
        let publications: PublicationProbe
    }

    @Test("Construction requires a fresh conductor runtime and a bounded queue")
    func requireFreshConductorRuntime() async throws {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let componentKey = try verificationKey(of: componentEvaluator)
        let bchKey = try verificationKey(of: bchEvaluator)
        let conductor = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: componentKey,
            bchSignatureVerificationKey: bchKey
        )
        let contributor = try Fixture.makeHarness(
            localRole: .contributor,
            verificationKey: componentKey,
            bchSignatureVerificationKey: bchKey
        )
        let dependencies = dependencies(
            componentEvaluator: componentEvaluator,
            bchEvaluator: bchEvaluator,
            previousOutputSource: RejectingPreviousOutputSource(),
            publications: PublicationProbe()
        )

        #expect(throws: Coordinator.InitializationError.invalidInputBufferLimit) {
            _ = try Coordinator(
                runtimeSession: try makeSession(conductor),
                dependencies: .init(
                    componentAuthorizationEvaluator: componentEvaluator,
                    bchSignatureAuthorizationEvaluator: bchEvaluator,
                    previousOutputSource: RejectingPreviousOutputSource(),
                    maximumPendingInputCount: 0,
                    handoffPublication: { _ in }
                )
            )
        }
        #expect(throws: Coordinator.InitializationError.localPeerIsNotConductor) {
            _ = try Coordinator(
                runtimeSession: try makeSession(contributor),
                dependencies: dependencies
            )
        }

        var advanced = try makeSession(conductor)
        let manifestRun = try aggregateRun(
            documentBytes: conductor.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: conductor.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: conductor
        )
        _ = admit(manifestRun, to: &advanced)
        #expect(throws: Coordinator.InitializationError.runtimeSessionNotFresh) {
            _ = try Coordinator(
                runtimeSession: advanced,
                dependencies: dependencies
            )
        }

        var terminal = try makeSession(conductor)
        _ = terminal.apply(input: .cancel)
        #expect(throws: Coordinator.InitializationError.runtimeSessionNotFresh) {
            _ = try Coordinator(
                runtimeSession: terminal,
                dependencies: dependencies
            )
        }
    }

    @Test("Manifest binds both attempt-scoped authorization keys")
    func rejectWrongAuthorizationKeys() async throws {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let componentKey = try verificationKey(of: componentEvaluator)
        let admission = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: componentKey,
            bchSignatureVerificationKey: try verificationKey(of: bchEvaluator)
        )
        let publications = PublicationProbe()
        let coordinator = try Coordinator(
            runtimeSession: try makeSession(admission),
            dependencies: dependencies(
                componentEvaluator: bchEvaluator,
                bchEvaluator: componentEvaluator,
                previousOutputSource: RejectingPreviousOutputSource(),
                publications: publications
            )
        )
        await coordinator.start()
        let manifestRun = try aggregateRun(
            documentBytes: admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: admission
        )
        try await submit(manifestRun, to: coordinator)
        await coordinator.waitForTermination()

        #expect(
            await coordinator.state
                == .terminal(.failed(.authorizationKeyMismatch))
        )
        #expect(await publications.values().isEmpty)
    }

    @Test(
        "Rehearse six-contributor conductor completion without network handoff",
        .timeLimit(.minutes(6))
    )
    func executeSixContributorConductor() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let publications = PublicationProbe(
            suspendingKind: .completeTransaction,
            suspension: suspension
        )
        let harness = try await makeHarness(publications: publications)
        await harness.coordinator.start()
        try await driveToCompletion(
            harness,
            completePublicationSuspension: suspension
        )
        await harness.coordinator.waitForTermination()

        #expect(await harness.coordinator.state == .terminal(.completed))
        #expect(
            await harness.coordinator.runtimeSessionState
                == .terminal(.completed)
        )
        let values = await harness.publications.values()
        let validations = await harness.publications.validationValues()
        #expect(validations.map(\.publication) == values)
        #expect(
            validations.allSatisfy {
                $0.attemptIdentifier == harness.admission.attemptIdentifier
                    && $0.generationIdentifier
                        == harness.admission.generationIdentifier
                    && $0.materialIdentifier
                        == harness.admission.materialIdentifier
                    && $0.conductor
                        == harness.admission.localControlIdentity
                    && $0.manifestBinding
                        == harness.admission.manifest.binding
            }
        )

        let alternateManifest = try Alpha.RoundManifest(
            core: harness.admission.manifest.core,
            signatures: MosaicManifestSignatureFixtures.manifestSignatures(
                for: harness.admission.manifest.core.roster,
                binding: harness.admission.manifest.binding,
                auxiliaryRandomnessByte: 0xA6
            )
        )
        #expect(alternateManifest.core == harness.admission.manifest.core)
        #expect(alternateManifest.binding != harness.admission.manifest.binding)
        let alternateManifestBridge = try makePublicationBridge(
            manifest: alternateManifest,
            admission: harness.admission
        )
        try await alternateManifestBridge.publishManifest(
            expiryUnixSeconds: 1_800_000_200
        )
        let coordinatorValidation = try #require(validations.first)
        await #expect(throws: Bridge.Failure.invalidPublication) {
            try await alternateManifestBridge.publish(
                coordinatorValidation,
                expiryUnixSeconds: 1_800_000_200
            )
        }
        #expect(
            values.compactMap { publication -> Alpha.AuthorizationResponseSet? in
                guard case let .authorizationResponseSet(value) = publication else {
                    return nil
                }
                return value
            }.count == harness.admission.election.result.roster.contributors.count
        )
        #expect(
            values.compactMap { publication -> OpalFusion.Mosaic.OpalV0.CommitmentSet? in
                guard case let .commitmentSet(value) = publication else {
                    return nil
                }
                return value
            } == [harness.materialized.prepared.commitmentSet]
        )
        #expect(
            values.compactMap { publication -> OpalFusion.Mosaic.OpalV0.ComponentSet? in
                guard case let .componentSet(value) = publication else {
                    return nil
                }
                return value
            } == [harness.materialized.prepared.componentSet]
        )
        #expect(
            values.compactMap { publication -> Alpha.BCHSignatureSet? in
                guard case let .bchSignatureSet(value) = publication else {
                    return nil
                }
                return value
            } == [harness.completion.signatureSet]
        )
        #expect(
            values.compactMap { publication -> Alpha.CompleteTransactionPayload? in
                guard case let .completeTransaction(value) = publication else {
                    return nil
                }
                return value
            } == [harness.completion.completePayload]
        )
        #expect(!(await harness.coordinator.requestRetry()))
    }

    @Test("Reject a response set that arrives before local issuance")
    func rejectPreIssuanceResponseSet() async throws {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let admission = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: try verificationKey(of: componentEvaluator),
            bchSignatureVerificationKey: try verificationKey(of: bchEvaluator)
        )
        let materialized = try MosaicMainnetAlphaFixtures
            .makeMaterializedPreparation(
                election: admission.election,
                manifest: admission.manifest,
                attemptIdentifier: admission.attemptIdentifier,
                generationIdentifier: admission.generationIdentifier,
                localContributor: try #require(
                    admission.manifest.core.orderedContributors.first
                ),
                localMaterialIdentifier: admission.materialIdentifier
            )
        let publications = PublicationProbe()
        let coordinator = try Coordinator(
            runtimeSession: try makeSession(admission),
            dependencies: dependencies(
                componentEvaluator: componentEvaluator,
                bchEvaluator: bchEvaluator,
                previousOutputSource: RejectingPreviousOutputSource(),
                publications: publications
            )
        )
        await coordinator.start()

        let manifestRun = try aggregateRun(
            documentBytes: admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: admission
        )
        try await submit(manifestRun, to: coordinator)
        let firstContributor = try #require(
            admission.manifest.core.orderedContributors.first
        )
        let material = try #require(
            materialized.materials[firstContributor]
        )
        let playerCommitRun = try aggregateRun(
            documentBytes: material.playerCommit.canonicalBytes,
            kind: .playerCommit,
            sender: material.contributor,
            phase: .walletReservation,
            sequence: 0,
            harness: admission
        )
        try await submit(playerCommitRun, to: coordinator)
        let responseSet = try Fixture.makeAuthorizationResponseSet(
            playerCommit: material.playerCommit
        )
        let responseRun = try aggregateRun(
            documentBytes: responseSet.canonicalBytes,
            kind: .authorizationResponseSet,
            sender: admission.election.result.roster.conductor,
            phase: .walletReservation,
            sequence: manifestRun.nextSequence,
            harness: admission
        )
        try await submit(responseRun, to: coordinator)
        await coordinator.waitForTermination()

        #expect(
            await coordinator.state
                == .terminal(.failed(.authorizationResponseSetMismatch))
        )
        #expect(await publications.values().isEmpty)
    }

    @Test(
        "Reject a substituted response set after local issuance",
        .timeLimit(.minutes(4))
    )
    func rejectSubstitutedResponseSet() async throws {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let admission = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: try verificationKey(of: componentEvaluator),
            bchSignatureVerificationKey: try verificationKey(of: bchEvaluator)
        )
        let materialized = try MosaicMainnetAlphaFixtures
            .makeMaterializedPreparation(
                election: admission.election,
                manifest: admission.manifest,
                attemptIdentifier: admission.attemptIdentifier,
                generationIdentifier: admission.generationIdentifier,
                localContributor: try #require(
                    admission.manifest.core.orderedContributors.first
                ),
                localMaterialIdentifier: admission.materialIdentifier
            )
        let publications = PublicationProbe()
        let coordinator = try Coordinator(
            runtimeSession: try makeSession(admission),
            dependencies: dependencies(
                componentEvaluator: componentEvaluator,
                bchEvaluator: bchEvaluator,
                previousOutputSource: RejectingPreviousOutputSource(),
                publications: publications,
                maximumPendingInputCount: 256
            )
        )
        await coordinator.start()

        let manifestRun = try aggregateRun(
            documentBytes: admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: admission
        )
        try await submit(manifestRun, to: coordinator)
        let materials = try admission.manifest.core.orderedContributors.map {
            try #require(materialized.materials[$0])
        }
        for material in materials {
            try await submit(
                aggregateRun(
                    documentBytes: material.playerCommit.canonicalBytes,
                    kind: .playerCommit,
                    sender: material.contributor,
                    phase: .walletReservation,
                    sequence: 0,
                    harness: admission
                ),
                to: coordinator
            )
        }
        await publications.wait(
            for: .authorizationResponseSet,
            count: materials.count
        )
        let substituted = try Fixture.makeAuthorizationResponseSet(
            playerCommit: materials[0].playerCommit,
            byteSeed: 0xA0
        )
        let responseRun = try aggregateRun(
            documentBytes: substituted.canonicalBytes,
            kind: .authorizationResponseSet,
            sender: admission.election.result.roster.conductor,
            phase: .walletReservation,
            sequence: manifestRun.nextSequence,
            harness: admission
        )
        try await submit(responseRun, to: coordinator)
        await coordinator.waitForTermination()

        #expect(
            await coordinator.state
                == .terminal(.failed(.authorizationResponseSetMismatch))
        )
        #expect(await publications.count(.commitmentSet) == 0)
    }

    @Test("A running in-place retry is terminal")
    func rejectRunningRetry() async throws {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let admission = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: try verificationKey(of: componentEvaluator),
            bchSignatureVerificationKey: try verificationKey(of: bchEvaluator)
        )
        let publications = PublicationProbe()
        let coordinator = try Coordinator(
            runtimeSession: try makeSession(admission),
            dependencies: dependencies(
                componentEvaluator: componentEvaluator,
                bchEvaluator: bchEvaluator,
                previousOutputSource: RejectingPreviousOutputSource(),
                publications: publications
            )
        )
        await coordinator.start()
        #expect(await coordinator.requestRetry())
        await coordinator.waitForTermination()

        #expect(
            await coordinator.state
                == .terminal(
                    .failed(.runtime(.inPlaceRetryNotPermitted))
                )
        )
        #expect(await publications.values().isEmpty)
    }

    @Test(
        "Publication failure terminates before semantic loopback",
        .timeLimit(.minutes(4))
    )
    func failAuthorizationResponsePublication() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let publications = PublicationProbe(
            failingKind: .authorizationResponseSet,
            suspendingKind: .authorizationResponseSet,
            suspension: suspension
        )
        let harness = try makeAuthorizationHarness(
            publications: publications
        )
        await harness.coordinator.start()
        _ = try await driveToAuthorizationResponses(harness)
        await suspension.waitUntilSuspended()
        #expect(await harness.coordinator.inputSourceDidTerminate(.failed))
        await harness.coordinator.stop()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(
                    .failed(.publicationFailed(.authorizationResponseSet))
                )
        )
        #expect(await publications.values().isEmpty)
    }

    @Test(
        "Stop drains an in-flight publication and suppresses later work",
        .timeLimit(.minutes(4))
    )
    func stopDuringAuthorizationResponsePublication() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let publications = PublicationProbe(
            suspendingKind: .authorizationResponseSet,
            suspension: suspension
        )
        let harness = try makeAuthorizationHarness(
            publications: publications
        )
        await harness.coordinator.start()
        _ = try await driveToAuthorizationResponses(harness)
        await suspension.waitUntilSuspended()
        await harness.coordinator.stop()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.cancelled(during: .walletReservation))
        )
        #expect(await publications.count(.authorizationResponseSet) == 1)
        #expect(await publications.count(.commitmentSet) == 0)
    }

    @Test(
        "A bounded-input overflow wins over an in-flight publication",
        .timeLimit(.minutes(4))
    )
    func failOnInputBufferOverflow() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let publications = PublicationProbe(
            suspendingKind: .authorizationResponseSet,
            suspension: suspension
        )
        let harness = try makeAuthorizationHarness(
            publications: publications,
            maximumPendingInputCount: 64
        )
        await harness.coordinator.start()
        let manifestSequence = try await driveToAuthorizationResponses(harness)
        await suspension.waitUntilSuspended()

        let material = try #require(
            harness.admission.manifest.core.orderedContributors.first.flatMap {
                harness.materialized.materials[$0]
            }
        )
        let responseSet = try Fixture.makeAuthorizationResponseSet(
            playerCommit: material.playerCommit
        )
        let responseRun = try aggregateRun(
            documentBytes: responseSet.canonicalBytes,
            kind: .authorizationResponseSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .walletReservation,
            sequence: manifestSequence,
            harness: harness.admission
        )
        for _ in 0 ..< 64 {
            guard await harness.coordinator.submitControl(
                responseRun.reservation
            ) else {
                throw TestFailure.inputRejected
            }
        }
        #expect(
            !(await harness.coordinator.submitControl(responseRun.reservation))
        )
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.inputBufferOverflow))
        )
        #expect(await publications.count(.authorizationResponseSet) == 1)
        #expect(await publications.count(.commitmentSet) == 0)
    }

    @Test(
        "Previous-output failure terminates before acknowledgement publication",
        .timeLimit(.minutes(6))
    )
    func failPreviousOutputResolution() async throws {
        let harness = try await makeHarness(
            previousOutputSource: RejectingPreviousOutputSource()
        )
        await harness.coordinator.start()
        try await driveToCompletion(harness, stopAfterComponentSet: true)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.previousOutputResolutionFailed))
        )
        #expect(
            await harness.publications.count(.preSignAcknowledgementSet) == 0
        )
        #expect(await harness.publications.count(.bchSignatureSet) == 0)
    }

    @Test(
        "Source loss wins over stop during previous-output resolution",
        .timeLimit(.minutes(6))
    )
    func preserveSourceLossDuringPreviousOutputResolution() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try await makeHarness(
            previousOutputSuspension: suspension
        )
        await harness.coordinator.start()
        try await driveToCompletion(harness, stopAfterComponentSet: true)
        await suspension.waitUntilSuspended()

        await harness.coordinator.inputSourceDidTerminate(.failed)
        await harness.coordinator.stop()
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(
                    .failed(.inputSourceTerminated(.failed))
                )
        )
        #expect(
            await harness.publications.count(.preSignAcknowledgementSet) == 0
        )
        #expect(await harness.publications.count(.bchSignatureSet) == 0)
        #expect(await harness.publications.count(.completeTransaction) == 0)
    }

    @Test("Input-source loss terminates once without conductor wallet authority")
    func failOnInputSourceLoss() async throws {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let admission = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: try verificationKey(of: componentEvaluator),
            bchSignatureVerificationKey: try verificationKey(of: bchEvaluator)
        )
        let publications = PublicationProbe()
        let coordinator = try Coordinator(
            runtimeSession: try makeSession(admission),
            dependencies: dependencies(
                componentEvaluator: componentEvaluator,
                bchEvaluator: bchEvaluator,
                previousOutputSource: RejectingPreviousOutputSource(),
                publications: publications
            )
        )
        await coordinator.start()
        await coordinator.inputSourceDidTerminate(.failed)
        await coordinator.waitForTermination()

        #expect(
            await coordinator.state
                == .terminal(
                    .failed(.inputSourceTerminated(.failed))
                )
        )
        #expect(await publications.values().isEmpty)
        #expect(!(await coordinator.requestRetry()))
    }

    private func makeHarness(
        previousOutputSource: (any OpalFusion.Host
            .MosaicPreviousOutputSource)? = nil,
        publications: PublicationProbe? = nil,
        previousOutputSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
    ) async throws -> Harness {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let admission = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: try verificationKey(of: componentEvaluator),
            bchSignatureVerificationKey: try verificationKey(of: bchEvaluator)
        )
        let localContributor = try #require(
            admission.manifest.core.orderedContributors.first
        )
        let materialized = try MosaicMainnetAlphaFixtures
            .makeMaterializedPreparation(
                election: admission.election,
                manifest: admission.manifest,
                attemptIdentifier: admission.attemptIdentifier,
                generationIdentifier: admission.generationIdentifier,
                localContributor: localContributor,
                localMaterialIdentifier: admission.materialIdentifier
            )
        let completion = try await ExecutionFixture.makeCompletion(
            admission: admission,
            materialized: materialized
        )
        let resolvedPreviousOutputSource: any OpalFusion.Host
            .MosaicPreviousOutputSource
        if let previousOutputSource {
            resolvedPreviousOutputSource = previousOutputSource
        } else if let previousOutputSuspension {
            resolvedPreviousOutputSource = SuspendingPreviousOutputSource(
                source: completion.previousOutputSource,
                suspension: previousOutputSuspension
            )
        } else {
            resolvedPreviousOutputSource = completion.previousOutputSource
        }
        let publications = publications ?? PublicationProbe()
        let coordinator = try Coordinator(
            runtimeSession: try makeSession(admission),
            dependencies: dependencies(
                componentEvaluator: componentEvaluator,
                bchEvaluator: bchEvaluator,
                previousOutputSource: resolvedPreviousOutputSource,
                publications: publications,
                maximumPendingInputCount: 256
            )
        )
        return .init(
            admission: admission,
            materialized: materialized,
            completion: completion,
            coordinator: coordinator,
            publications: publications
        )
    }

    private func makeAuthorizationHarness(
        publications: PublicationProbe,
        maximumPendingInputCount: Int = 256
    ) throws -> AuthorizationHarness {
        let componentEvaluator = try MosaicMainnetAlphaFixtures
            .authorizationEvaluator()
        let bchEvaluator = try MosaicMainnetAlphaFixtures
            .bchSignatureAuthorizationEvaluator()
        let admission = try Fixture.makeHarness(
            localRole: .conductor,
            verificationKey: try verificationKey(of: componentEvaluator),
            bchSignatureVerificationKey: try verificationKey(of: bchEvaluator)
        )
        let localContributor = try #require(
            admission.manifest.core.orderedContributors.first
        )
        let materialized = try MosaicMainnetAlphaFixtures
            .makeMaterializedPreparation(
                election: admission.election,
                manifest: admission.manifest,
                attemptIdentifier: admission.attemptIdentifier,
                generationIdentifier: admission.generationIdentifier,
                localContributor: localContributor,
                localMaterialIdentifier: admission.materialIdentifier
            )
        let coordinator = try Coordinator(
            runtimeSession: try makeSession(admission),
            dependencies: dependencies(
                componentEvaluator: componentEvaluator,
                bchEvaluator: bchEvaluator,
                previousOutputSource: RejectingPreviousOutputSource(),
                publications: publications,
                maximumPendingInputCount: maximumPendingInputCount
            )
        )
        return .init(
            admission: admission,
            materialized: materialized,
            coordinator: coordinator,
            publications: publications
        )
    }

    private func driveToAuthorizationResponses(
        _ harness: AuthorizationHarness
    ) async throws -> UInt64 {
        let manifestRun = try aggregateRun(
            documentBytes: harness.admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: harness.admission
        )
        try await submit(manifestRun, to: harness.coordinator)
        let materials = try harness.admission.manifest.core
            .orderedContributors.map {
                try #require(harness.materialized.materials[$0])
            }
        for material in materials {
            try await submit(
                aggregateRun(
                    documentBytes: material.playerCommit.canonicalBytes,
                    kind: .playerCommit,
                    sender: material.contributor,
                    phase: .walletReservation,
                    sequence: 0,
                    harness: harness.admission
                ),
                to: harness.coordinator
            )
        }
        return manifestRun.nextSequence
    }

    private func dependencies(
        componentEvaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator,
        bchEvaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator,
        previousOutputSource: any OpalFusion.Host.MosaicPreviousOutputSource,
        publications: PublicationProbe,
        maximumPendingInputCount: Int = 16
    ) -> Coordinator.Dependencies {
        .init(
            componentAuthorizationEvaluator: componentEvaluator,
            bchSignatureAuthorizationEvaluator: bchEvaluator,
            previousOutputSource: previousOutputSource,
            maximumPendingInputCount: maximumPendingInputCount,
            handoffPublication: { publication in
                try await publications.publish(publication)
            }
        )
    }

    private func makeSession(_ harness: Fixture.Harness) throws
        -> Alpha.RuntimeSession {
        try .init(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: harness.election
            ),
            attemptIdentifier: harness.attemptIdentifier,
            generationIdentifier: harness.generationIdentifier,
            materialIdentifier: harness.materialIdentifier,
            localControlIdentity: harness.localControlIdentity,
            proposalValidation: harness.proposalValidation
        )
    }

    private func makePublicationBridge(
        manifest: Alpha.RoundManifest,
        admission: Fixture.Harness
    ) throws -> Bridge {
        let bootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: admission.materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            proposalValidation: admission.proposalValidation
        )
        let context = try Bridge.Context(
            validating: manifest,
            against: bootstrap
        )
        let controlScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(
                for: admission.localControlIdentity
            )
        )
        let controlSigningKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: scalarBytes(Int(controlScalar))
        )
        let eventSigningKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: scalarBytes(20)
        )
        let recipients = try context.roster.controlIdentities.enumerated().map {
            index, identity in
            let recipientKey = try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: scalarBytes(30 + index)
            )
            return Bridge.Recipient(
                controlIdentity: identity,
                eventVerificationKey: recipientKey.bip340VerificationKey
            )
        }
        return try Bridge(
            context: context,
            controlSigningKey: controlSigningKey,
            eventSigningKey: eventSigningKey,
            recipients: recipients,
            dependencies: .init(
                makeLayerTimestamps: { _ in
                    try .init(
                        phaseStartUnixSeconds: context.phaseStartUnixSeconds,
                        currentUnixSeconds: 1_800_000_100,
                        sealCreatedAt: 1_800_000_098,
                        giftWrapCreatedAt: 1_800_000_099
                    )
                },
                makeSignatureAuxiliaryRandomness: {
                    try .init(
                        rawRepresentation: Data(repeating: 0xA5, count: 32)
                    )
                },
                handoffGiftWrapBatch: { _ in }
            )
        )
    }

    private func driveToCompletion(
        _ harness: Harness,
        stopAfterComponentSet: Bool = false,
        completePublicationSuspension:
            MosaicRuntimeCoordinatorSuspensionProbe? = nil
    ) async throws {
        var conductorSequence: UInt64 = 0
        var contributorSequences: [
            OpalFusion.Mosaic.Attempt.ControlIdentity: UInt64
        ] = [:]

        let manifestRun = try aggregateRun(
            documentBytes: harness.admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: conductorSequence,
            harness: harness.admission
        )
        try await submit(manifestRun, to: harness.coordinator)
        conductorSequence = manifestRun.nextSequence

        let materials = try harness.admission.manifest.core
            .orderedContributors.map {
                try #require(harness.materialized.materials[$0])
            }
        for material in materials {
            let run = try aggregateRun(
                documentBytes: material.playerCommit.canonicalBytes,
                kind: .playerCommit,
                sender: material.contributor,
                phase: .walletReservation,
                sequence: 0,
                harness: harness.admission
            )
            try await submit(run, to: harness.coordinator)
            contributorSequences[material.contributor] = run.nextSequence
        }

        await harness.publications.wait(
            for: .authorizationResponseSet,
            count: materials.count
        )
        let responseSets = await harness.publications.values().compactMap {
            publication -> Alpha.AuthorizationResponseSet? in
            guard case let .authorizationResponseSet(value) = publication else {
                return nil
            }
            return value
        }
        #expect(responseSets.map(\.contributor) == materials.map(\.contributor))
        #expect(await harness.publications.count(.commitmentSet) == 0)

        var validations: [
            OpalFusion.Mosaic.Attempt.ControlIdentity:
                Alpha.AuthorizationResponseSetMaterialValidation
        ] = [:]
        for (material, responseSet) in zip(materials, responseSets) {
            validations[material.contributor] = try .init(
                validating: responseSet,
                material: material
            )
            let run = try aggregateRun(
                documentBytes: responseSet.canonicalBytes,
                kind: .authorizationResponseSet,
                sender: harness.admission.election.result.roster.conductor,
                phase: .walletReservation,
                sequence: conductorSequence,
                harness: harness.admission
            )
            try await submit(run, to: harness.coordinator)
            conductorSequence = run.nextSequence
        }

        await harness.publications.wait(for: .commitmentSet)
        let commitmentSet = try #require(
            await harness.publications.values().compactMap {
                publication -> OpalFusion.Mosaic.OpalV0.CommitmentSet? in
                guard case let .commitmentSet(value) = publication else {
                    return nil
                }
                return value
            }.first
        )
        let commitmentRun = try aggregateRun(
            documentBytes: commitmentSet.canonicalBytes,
            kind: .commitmentSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .groupedCommitment,
            sequence: conductorSequence,
            harness: harness.admission
        )
        try await submit(commitmentRun, to: harness.coordinator)
        conductorSequence = commitmentRun.nextSequence

        var messageIndex = 0
        for material in materials {
            let validation = try #require(validations[material.contributor])
            for slot in material.slots {
                let token = validation.componentAuthorizationTokens[slot.slot]
                let payload = try Alpha.AnonymousComponentPayload(
                    roundIdentifier:
                        harness.admission.manifest.core.roundIdentifier,
                    authorizationToken: token,
                    component: slot.component
                )
                let communicationKey = [UInt8](
                    try OpalCrypto.Secp256k1.SigningKey(
                        rawRepresentation: Data(
                            scalarBytes(60_000 + messageIndex)
                        )
                    ).publicKey.compressedRepresentation
                )
                let envelope = try Alpha.AnonymousEnvelope(
                    roundIdentifier:
                        harness.admission.manifest.core.roundIdentifier,
                    phase: .anonymousComponentSubmission,
                    senderCommunicationPublicKey: communicationKey,
                    recipientEventIdentity: slot.recipientEventIdentity,
                    sequence: 0,
                    payloadType: .anonymousComponent,
                    expiryUnixSeconds: 1_800_000_060,
                    payload: try Alpha.CanonicalWireCodec
                        .encodeAnonymousComponent(payload)
                )
                let accepted = await harness.coordinator
                    .submitAnonymous(
                        .init(
                            attemptIdentifier:
                                harness.admission.attemptIdentifier,
                            generationIdentifier:
                                harness.admission.generationIdentifier,
                            envelope: envelope,
                            authenticatedOuterEventIdentity:
                                Array(communicationKey.dropFirst()),
                            authenticatedRecipientEventIdentity:
                                slot.recipientEventIdentity,
                            authenticatedMessageIdentifier: try .init(
                                bytes: MosaicUnsignedTransactionTranscriptFixtures
                                    .indexedDigest(30_000 + messageIndex)
                            ),
                            currentUnixSeconds: 1_800_000_000
                        )
                    )
                #expect(accepted)
                messageIndex += 1
            }
        }

        await harness.publications.wait(for: .componentSet)
        let componentSet = try #require(
            await harness.publications.values().compactMap {
                publication -> OpalFusion.Mosaic.OpalV0.ComponentSet? in
                guard case let .componentSet(value) = publication else {
                    return nil
                }
                return value
            }.first
        )
        let componentRun = try aggregateRun(
            documentBytes: componentSet.canonicalBytes,
            kind: .componentSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .anonymousComponentSubmission,
            sequence: conductorSequence,
            harness: harness.admission
        )
        try await submit(componentRun, to: harness.coordinator)
        conductorSequence = componentRun.nextSequence

        if stopAfterComponentSet {
            return
        }

        let acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: harness.admission.election.result.roster.contributors,
                binding: harness.admission.manifest.binding,
                transcriptRoot: harness.materialized.prepared.transcript
                    .transcriptRoot,
                profile: .opalMainnetAlpha
            )
        for acknowledgement in acknowledgements {
            let sequence = try #require(
                contributorSequences[acknowledgement.contributor]
            )
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
                roundIdentifier:
                    harness.admission.manifest.core.roundIdentifier
            )
            #expect(
                await harness.coordinator.submitControl(
                    Fixture.controlDelivery(
                        envelope: envelope,
                        harness: harness.admission
                    )
                )
            )
        }

        await harness.publications.wait(for: .preSignAcknowledgementSet)
        let acknowledgementSet = try #require(
            await harness.publications.values().compactMap {
                publication -> Alpha.PreSignAcknowledgementSet? in
                guard case let .preSignAcknowledgementSet(value) = publication
                else { return nil }
                return value
            }.first
        )
        let acknowledgementRun = try aggregateRun(
            documentBytes: acknowledgementSet.canonicalBytes,
            kind: .preSignAcknowledgementSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .transcriptAgreement,
            sequence: conductorSequence,
            harness: harness.admission
        )
        try await submit(acknowledgementRun, to: harness.coordinator)
        conductorSequence = acknowledgementRun.nextSequence

        let inputComponents = harness.materialized.prepared.componentSet
            .components.compactMap {
                component -> OpalFusion.Mosaic.OpalV0.Component? in
                if case .input = component.payload { return component }
                return nil
            }.sorted { lhs, rhs in
                guard case let .input(left) = lhs.payload,
                      case let .input(right) = rhs.payload else { return false }
                if left.previousTransactionHash != right.previousTransactionHash {
                    return left.previousTransactionHash.lexicographicallyPrecedes(
                        right.previousTransactionHash
                    )
                }
                return left.outputIndex < right.outputIndex
            }
        for (inputIndex, component) in inputComponents.enumerated() {
            let material = try #require(
                materials.first { material in
                    material.slots.contains { $0.component == component }
                }
            )
            let slot = try #require(
                material.slots.first { $0.component == component }
            )
            let validation = try #require(validations[material.contributor])
            let submission = try Alpha.BCHSignatureSubmission(
                transcriptRoot: harness.materialized.prepared.transcript
                    .transcriptRoot.validatedBytes,
                authorizationToken:
                    validation.bchSignatureAuthorizationTokens[slot.slot],
                entry: harness.completion.signatureSet.entries[inputIndex]
            )
            let communicationKey = try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: scalarBytes(80_000 + inputIndex)
            ).publicKey.compressedRepresentation
            let envelope = try Alpha.AnonymousEnvelope(
                roundIdentifier:
                    harness.admission.manifest.core.roundIdentifier,
                phase: .bchSigning,
                senderCommunicationPublicKey: [UInt8](communicationKey),
                recipientEventIdentity: slot.recipientEventIdentity,
                sequence: 1,
                payloadType: .bchSignatureSubmission,
                expiryUnixSeconds: 1_800_000_060,
                payload: Alpha.CanonicalWireCodec
                    .encodeBCHSignatureSubmission(submission)
            )
            #expect(
                await harness.coordinator.submitAnonymous(
                    .init(
                        attemptIdentifier: harness.admission.attemptIdentifier,
                        generationIdentifier:
                            harness.admission.generationIdentifier,
                        envelope: envelope,
                        authenticatedOuterEventIdentity:
                            Array(communicationKey.dropFirst()),
                        authenticatedRecipientEventIdentity:
                            slot.recipientEventIdentity,
                        authenticatedMessageIdentifier: try .init(
                            bytes: MosaicUnsignedTransactionTranscriptFixtures
                                .indexedDigest(31_000 + inputIndex)
                        ),
                        currentUnixSeconds: 1_800_000_000
                    )
                )
            )
        }

        await harness.publications.wait(for: .bchSignatureSet)
        let signatureSet = try #require(
            await harness.publications.values().compactMap {
                publication -> Alpha.BCHSignatureSet? in
                guard case let .bchSignatureSet(value) = publication else {
                    return nil
                }
                return value
            }.first
        )
        let signatureRun = try aggregateRun(
            documentBytes: signatureSet.canonicalBytes,
            kind: .bchSignatureSet,
            sender: harness.admission.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: conductorSequence,
            harness: harness.admission
        )
        try await submit(signatureRun, to: harness.coordinator)
        conductorSequence = signatureRun.nextSequence

        let completePayload: Alpha.CompleteTransactionPayload
        if let completePublicationSuspension {
            await completePublicationSuspension.waitUntilSuspended()
            completePayload = harness.completion.completePayload
        } else {
            await harness.publications.wait(for: .completeTransaction)
            completePayload = try #require(
                await harness.publications.values().compactMap {
                    publication -> Alpha.CompleteTransactionPayload? in
                    guard case let .completeTransaction(value) = publication
                    else { return nil }
                    return value
                }.first
            )
        }
        let completeRun = try aggregateRun(
            documentBytes: completePayload.canonicalBytes,
            kind: .completeTransaction,
            sender: harness.admission.election.result.roster.conductor,
            phase: .bchSigning,
            sequence: conductorSequence,
            harness: harness.admission
        )
        try await submit(completeRun, to: harness.coordinator)
        await harness.coordinator.inputSourceDidTerminate(.finished)
        await completePublicationSuspension?.resume()
    }

    private func aggregateRun(
        documentBytes: [UInt8],
        kind: Alpha.AggregateKind,
        sender: OpalFusion.Mosaic.Attempt.ControlIdentity,
        phase: OpalFusion.Mosaic.Attempt.Phase,
        sequence: UInt64,
        harness: Fixture.Harness
    ) throws -> Fixture.AggregateRun {
        try Fixture.aggregateRun(
            canonicalBytes: documentBytes,
            kind: kind,
            sender: sender,
            phase: phase,
            sequence: sequence,
            harness: harness
        )
    }

    private func submit(
        _ run: Fixture.AggregateRun,
        to coordinator: Coordinator
    ) async throws {
        guard await coordinator.submitControl(run.reservation) else {
            throw TestFailure.inputRejected
        }
        for fragment in run.fragments {
            guard await coordinator.submitControl(fragment) else {
                throw TestFailure.inputRejected
            }
        }
    }

    private func admit(
        _ run: Fixture.AggregateRun,
        to session: inout Alpha.RuntimeSession
    ) -> [Alpha.RuntimeSession.Effect] {
        var effects = session.apply(input: .control(run.reservation))
        for fragment in run.fragments {
            effects.append(
                contentsOf: session.apply(input: .control(fragment))
            )
        }
        return effects
    }

    private func scalarBytes(_ scalar: Int) -> Data {
        precondition(scalar > 0)
        var value = UInt32(scalar).bigEndian
        var bytes = Data(repeating: 0, count: 28)
        withUnsafeBytes(of: &value) { bytes.append(contentsOf: $0) }
        return bytes
    }

    private enum TestFailure: Error {
        case authorizationEvaluatorUnavailable
        case inputRejected
    }

    private func verificationKey(
        of evaluator: OpalFusion.Mosaic.OpalV0.AuthorizationEvaluator
    ) throws -> OpalCrypto.RSABSSA.VerificationKey {
        guard let verificationKey = evaluator.verificationKey else {
            throw TestFailure.authorizationEvaluatorUnavailable
        }
        return verificationKey
    }
}
