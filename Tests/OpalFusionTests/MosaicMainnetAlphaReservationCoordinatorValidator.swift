// MosaicMainnetAlphaReservationCoordinatorValidator.swift

import Foundation
import Synchronization
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha reservation coordinator")
struct MosaicMainnetAlphaReservationCoordinatorValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Coordinator = Alpha.ReservationCoordinator
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Session = Alpha.RuntimeSession

    private final class SignalProbe: Sendable {
        enum Signal: CaseIterable, Hashable, Sendable {
            case publicationStarted
            case validationAccepted
        }

        private let counts = Mutex<[Signal: Int]>([:])
        private let signalStreams: [Signal: AsyncStream<Void>]
        private let signalContinuations: [Signal: AsyncStream<Void>.Continuation]

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

        func record(_ signal: Signal) {
            counts.withLock { $0[signal, default: 0] += 1 }
            signalContinuations[signal]?.yield()
        }

        func wait(for signal: Signal) async {
            guard count(signal) == 0,
                  let stream = signalStreams[signal] else {
                return
            }
            for await _ in stream {
                return
            }
        }

        func count(_ signal: Signal) -> Int {
            counts.withLock { $0[signal, default: 0] }
        }
    }

    private struct ReferenceValidator:
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

    private struct Harness {
        let admission: Fixture.Harness
        let materialIdentifier: Session.MaterialIdentifier
        let playerCommit: Alpha.PlayerCommit
        let lease: OpalFusion.Host.MosaicReservationLease
        let host: MosaicRuntimeCoordinatorHostProbe
        let signals: SignalProbe
        let externalValidation: Session.ReservationPublicationValidation
        let coordinator: Coordinator
    }

    enum ReservationRequestSubstitution: CaseIterable, Sendable {
        case attemptIdentifier
        case networkGenesisHash
        case roundIdentifier
        case expiration
        case componentCount
        case feeRate
        case minimumExcessFee
        case maximumExcessFee
        case requiredExcessFee
        case transactionProfile
    }

    private enum PublicationLeaseSubstitution {
        case foreignReference
        case sameReferenceDifferentContents
    }

    @Test(
        "Bind the actual host lease to one sealed publication",
        .timeLimit(.minutes(1))
    )
    func bindActualLeaseToPublication() async throws {
        let harness = try makeHarness()
        await harness.coordinator.start()

        #expect(
            await harness.coordinator.submit(
                .reservationPublicationValidated(harness.externalValidation)
            ) == false
        )
        try await submitManifest(harness)
        await harness.signals.wait(for: .validationAccepted)

        #expect(await harness.host.reservationRequests.count == 1)
        #expect(harness.signals.count(.publicationStarted) == 1)
        #expect(harness.signals.count(.validationAccepted) == 1)
        #expect(
            await harness.coordinator.reservationLifecycle
                == .reserved(harness.lease)
        )
        #expect(
            await harness.coordinator.runtimeSessionState
                == .active(.walletReservation)
        )
        #expect(await harness.host.signingRequests.isEmpty)
        #expect(await harness.host.completeCommits.isEmpty)

        try await submitManifest(harness)
        #expect(await harness.host.reservationRequests.count == 1)
        #expect(harness.signals.count(.publicationStarted) == 1)

        await harness.coordinator.stop()
        await harness.coordinator.waitForTermination()
        #expect(
            await harness.coordinator.state
                == .terminal(.cancelled(during: .walletReservation))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
    }

    @Test(
        "Reject a sealed token for a different lease and release the actual lease",
        .timeLimit(.minutes(1))
    )
    func rejectForeignLeaseValidation() async throws {
        let harness = try makeHarness(
            publicationLeaseSubstitution: .foreignReference
        )
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.reservationPublicationLeaseMismatch))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(harness.signals.count(.publicationStarted) == 1)
        #expect(harness.signals.count(.validationAccepted) == 0)
    }

    @Test(
        "Reject substituted lease contents under the actual reference",
        .timeLimit(.minutes(1))
    )
    func rejectSameReferenceLeaseSubstitution() async throws {
        let harness = try makeHarness(
            publicationLeaseSubstitution: .sameReferenceDifferentContents
        )
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.reservationPublicationLeaseMismatch))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(harness.signals.count(.validationAccepted) == 0)
    }

    @Test(
        "Reject a host lease whose expiry differs from the validated request",
        arguments: [-1.0, 1.0]
    )
    func rejectHostLeaseExpirationMismatch(
        _ expirationOffset: TimeInterval
    ) async throws {
        let harness = try makeHarness(
            hostLeaseExpirationOffset: expirationOffset
        )
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.reservationLeaseExpirationMismatch))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(harness.signals.count(.publicationStarted) == 0)
        #expect(harness.signals.count(.validationAccepted) == 0)
    }

    @Test(
        "Cancellation releases a late host lease without publishing",
        .timeLimit(.minutes(1))
    )
    func releaseLateLeaseAfterCancellation() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(reserveSuspension: suspension)
        await harness.coordinator.start()
        try await submitManifest(harness)
        await suspension.waitUntilSuspended()

        await harness.coordinator.stop()
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(
            await harness.coordinator.reservationLifecycle
                == .reservationInFlight
        )
        #expect(harness.signals.count(.validationAccepted) == 0)
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.cancelled(during: .walletReservation))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(harness.signals.count(.publicationStarted) == 0)
        #expect(harness.signals.count(.validationAccepted) == 0)
    }

    @Test(
        "A claimed publication finishes once before cancellation releases",
        .timeLimit(.minutes(1))
    )
    func finishClaimedPublicationBeforeCancellation() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let harness = try makeHarness(publicationSuspension: suspension)
        await harness.coordinator.start()
        try await submitManifest(harness)
        await suspension.waitUntilSuspended()

        await harness.coordinator.stop()
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(
            await harness.coordinator.reservationLifecycle
                == .reserved(harness.lease)
        )
        #expect(harness.signals.count(.validationAccepted) == 0)
        await suspension.resume()
        await harness.coordinator.waitForTermination()

        #expect(harness.signals.count(.publicationStarted) == 1)
        #expect(harness.signals.count(.validationAccepted) == 0)
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(
            await harness.coordinator.state
                == .terminal(.cancelled(during: .walletReservation))
        )
    }

    @Test(
        "Reject every substituted coordinator-bound reservation request term",
        arguments: ReservationRequestSubstitution.allCases
    )
    func rejectInvalidReservationRequest(
        _ substitution: ReservationRequestSubstitution
    ) async throws {
        let harness = try makeHarness(
            reservationRequestSubstitution: substitution
        )
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.invalidReservationRequest))
        )
        #expect(await harness.host.reservationRequests.isEmpty)
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(harness.signals.count(.publicationStarted) == 0)
    }

    @Test(
        "A host reservation failure terminates without publication or release",
        .timeLimit(.minutes(1))
    )
    func failClosedWhenHostReservationFails() async throws {
        let harness = try makeHarness()
        await harness.host.failReservation()
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.reservationFailed))
        )
        #expect(await harness.host.reservationRequests.count == 1)
        #expect(await harness.host.releasedReferences.isEmpty)
        #expect(harness.signals.count(.publicationStarted) == 0)
    }

    @Test(
        "A publication failure releases the exact host lease before terminal failure",
        .timeLimit(.minutes(1))
    )
    func releaseAfterPublicationFailure() async throws {
        let harness = try makeHarness(failPublication: true)
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.reservationPublicationFailed))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
        #expect(harness.signals.count(.publicationStarted) == 1)
        #expect(harness.signals.count(.validationAccepted) == 0)
    }

    @Test(
        "A terminal retry input releases the lease before exposing runtime failure",
        .timeLimit(.minutes(1))
    )
    func releaseBeforeRuntimeFailure() async throws {
        let harness = try makeHarness()
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.signals.wait(for: .validationAccepted)

        #expect(await harness.coordinator.submit(.retryRequested))
        await harness.coordinator.waitForTermination()

        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.runtime(.inPlaceRetryNotPermitted)))
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
    }

    @Test(
        "A failed release requires recovery for the exact host lease",
        .timeLimit(.minutes(1))
    )
    func requireRecoveryAfterReleaseFailure() async throws {
        let harness = try makeHarness()
        await harness.host.failRelease()
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.signals.wait(for: .validationAccepted)

        await harness.coordinator.stop()
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
            await harness.coordinator.reservationLifecycle
                == .releaseFailed(harness.lease.reference)
        )
        #expect(
            await harness.host.releasedReferences
                == [harness.lease.reference]
        )
    }

    @Test("Reject a conductor before invoking wallet authority")
    func rejectConductorCoordinator() throws {
        let admission = try Fixture.makeHarness(localRole: .conductor)
        let materialIdentifier = Session.MaterialIdentifier(
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
        let lease = try makeLease()
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: lease,
            finalizedTransaction: .init(signedFusionTransactionBytes: [0x01])
        )

        #expect(throws: Coordinator.InitializationError.localPeerIsNotContributor) {
            _ = try Coordinator(
                runtimeSession: session,
                dependencies: .init(
                    transactionHost: host,
                    expectedReservationExpiration: lease.expiresAt,
                    makeReservationRequest: { _ in
                        throw ProbeFailure.unexpectedInvocation
                    },
                    validateAndPublishReservedContribution: { _, _ in
                        throw ProbeFailure.unexpectedInvocation
                    }
                )
            )
        }
    }

    @Test("Reject an already-advanced runtime before invoking wallet authority")
    func rejectAdvancedRuntime() async throws {
        let admission = try Fixture.makeHarness(localRole: .contributor)
        var session = try makeRuntimeSession(admission: admission)
        let run = try Fixture.aggregateRun(
            canonicalBytes: admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: admission
        )
        _ = session.apply(input: .control(run.reservation))
        for fragment in run.fragments {
            _ = session.apply(input: .control(fragment))
        }
        #expect(session.state == .active(.walletReservation))

        let host = try makeHost()
        #expect(throws: Coordinator.InitializationError.runtimeSessionNotFresh) {
            _ = try Coordinator(
                runtimeSession: session,
                dependencies: rejectingDependencies(host: host)
            )
        }
        #expect(await host.reservationRequests.isEmpty)
    }

    @Test("Reject a terminal runtime before invoking wallet authority")
    func rejectTerminalRuntime() async throws {
        let admission = try Fixture.makeHarness(localRole: .contributor)
        var session = try makeRuntimeSession(admission: admission)
        _ = session.apply(input: .cancel)
        #expect(
            session.state == .terminal(
                .cancelled(during: .manifestAgreement)
            )
        )

        let host = try makeHost()
        #expect(throws: Coordinator.InitializationError.runtimeSessionNotFresh) {
            _ = try Coordinator(
                runtimeSession: session,
                dependencies: rejectingDependencies(host: host)
            )
        }
        #expect(await host.reservationRequests.isEmpty)
    }

    private func makeHarness(
        reserveSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        publicationSuspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil,
        publicationLeaseSubstitution: PublicationLeaseSubstitution? = nil,
        reservationRequestSubstitution: ReservationRequestSubstitution? = nil,
        hostLeaseExpirationOffset: TimeInterval = 0,
        failPublication: Bool = false
    ) throws -> Harness {
        let admission = try Fixture.makeHarness(localRole: .contributor)
        let materialIdentifier = Session.MaterialIdentifier(
            opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
        )
        let session = try makeRuntimeSession(
            admission: admission,
            materialIdentifier: materialIdentifier
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: admission.election.result.roster,
            manifest: admission.manifest.binding,
            profile: .opalMainnetAlpha
        )
        let playerCommit = try #require(
            Fixture.makePlayerCommits(
                harness: admission,
                commitmentSet: preparation.commitmentSet
            ).first {
                $0.contributor == admission.localControlIdentity
            }
        )
        let expectedExpiration = Date(timeIntervalSince1970: 1_900_000_000)
        let lease = try makeLease(
            expiresAt: expectedExpiration.addingTimeInterval(
                hostLeaseExpirationOffset
            )
        )
        let foreignReference = reservationReference(finalByte: 0xC2)
        let publicationLease: OpalFusion.Host.MosaicReservationLease
        switch publicationLeaseSubstitution {
        case .foreignReference:
            publicationLease = try makeLease(reference: foreignReference)
        case .sameReferenceDifferentContents:
            publicationLease = try makeLease(
                reference: lease.reference,
                inputLockingScript: [0x52]
            )
        case nil:
            publicationLease = lease
        }
        let externalRequest = Session.ReservationPublicationRequest(
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: materialIdentifier,
            contributor: admission.localControlIdentity,
            manifest: admission.manifest,
            reservationLease: lease,
            playerCommit: playerCommit
        )
        let externalValidation = try Session.ReservationPublicationValidation(
            validating: externalRequest,
            using: ReferenceValidator(expectedReference: lease.reference)
        )
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: lease,
            finalizedTransaction: .init(signedFusionTransactionBytes: [0x01]),
            reserveSuspension: reserveSuspension
        )
        let signals = SignalProbe()
        let coordinator = try Coordinator(
            runtimeSession: session,
            dependencies: .init(
                transactionHost: host,
                expectedReservationExpiration: expectedExpiration,
                makeReservationRequest: { eligibility in
                    try makeReservationRequest(
                        eligibility: eligibility,
                        expiresAt: expectedExpiration,
                        substituting: reservationRequestSubstitution
                    )
                },
                validateAndPublishReservedContribution: {
                    eligibility,
                    receivedLease in
                    guard receivedLease == lease else {
                        throw ProbeFailure.unexpectedInvocation
                    }
                    signals.record(.publicationStarted)
                    await publicationSuspension?.suspendIfArmed()
                    guard !failPublication else {
                        throw ProbeFailure.publication
                    }
                    let request = Session.ReservationPublicationRequest(
                        attemptIdentifier: eligibility.context.attemptIdentifier,
                        generationIdentifier: eligibility.context
                            .generationIdentifier,
                        materialIdentifier: eligibility.context.materialIdentifier,
                        contributor: eligibility.context.localControlIdentity,
                        manifest: eligibility.manifest,
                        reservationLease: publicationLease,
                        playerCommit: playerCommit
                    )
                    return try Session.ReservationPublicationValidation(
                        validating: request,
                        using: ReferenceValidator(
                            expectedReference: publicationLease.reference
                        )
                    )
                },
                runtimeEffectObserver: { effect in
                    guard case .reservationPublicationAccepted = effect else {
                        return
                    }
                    signals.record(.validationAccepted)
                }
            )
        )
        return .init(
            admission: admission,
            materialIdentifier: materialIdentifier,
            playerCommit: playerCommit,
            lease: lease,
            host: host,
            signals: signals,
            externalValidation: externalValidation,
            coordinator: coordinator
        )
    }

    private func makeRuntimeSession(
        admission: Fixture.Harness,
        materialIdentifier: Session.MaterialIdentifier = .init(
            opaqueBytes: [UInt8](repeating: 0xA3, count: 32)
        )
    ) throws -> Session {
        try Session(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            proposalValidation: admission.proposalValidation
        )
    }

    private func makeHost() throws -> MosaicRuntimeCoordinatorHostProbe {
        MosaicRuntimeCoordinatorHostProbe(
            lease: try makeLease(),
            finalizedTransaction: .init(signedFusionTransactionBytes: [0x01])
        )
    }

    private func rejectingDependencies(
        host: MosaicRuntimeCoordinatorHostProbe
    ) -> Coordinator.Dependencies {
        .init(
            transactionHost: host,
            expectedReservationExpiration: Date(
                timeIntervalSince1970: 1_900_000_000
            ),
            makeReservationRequest: { _ in
                throw ProbeFailure.unexpectedInvocation
            },
            validateAndPublishReservedContribution: { _, _ in
                throw ProbeFailure.unexpectedInvocation
            }
        )
    }

    private func submitManifest(_ harness: Harness) async throws {
        let run = try Fixture.aggregateRun(
            canonicalBytes: harness.admission.manifest.canonicalBytes,
            kind: .completeManifest,
            sender: harness.admission.election.result.roster.conductor,
            phase: .manifestAgreement,
            sequence: 0,
            harness: harness.admission
        )
        #expect(await harness.coordinator.submit(.control(run.reservation)))
        for fragment in run.fragments {
            #expect(await harness.coordinator.submit(.control(fragment)))
        }
    }

    private func makeReservationRequest(
        eligibility: Coordinator.ReservationEligibility,
        expiresAt: Date,
        substituting substitution: ReservationRequestSubstitution?
    ) throws -> OpalFusion.Host.MosaicReservationRequest {
        let manifest = eligibility.manifest
        var attemptIdentifier = eligibility.context.attemptIdentifier
            .validatedBytes
        var networkGenesisHash = manifest.core.networkGenesisHash
        var roundIdentifier = manifest.core.roundIdentifier
        var reservationExpiration = expiresAt
        var componentCount = Int(manifest.core.componentCount)
        var feeRateSatoshisPerByte = manifest.core.feeRateSatoshisPerByte
        var minimumExcessFeeSatoshis = manifest.core
            .minimumExcessFeeSatoshis
        var maximumExcessFeeSatoshis = manifest.core
            .maximumExcessFeeSatoshis
        var requiredExcessFeeSatoshis = try Alpha.ContributionFeePolicy
            .requiredExcessFeeSatoshis(
                for: eligibility.context.localControlIdentity,
                in: eligibility.context.roster
            )
        var transactionProfileIdentifier = manifest.core
            .transactionProfileIdentifier

        switch substitution {
        case .attemptIdentifier:
            attemptIdentifier[0] ^= 0x01
        case .networkGenesisHash:
            networkGenesisHash[0] ^= 0x01
        case .roundIdentifier:
            roundIdentifier[0] ^= 0x01
        case .expiration:
            reservationExpiration.addTimeInterval(1)
        case .componentCount:
            componentCount += 1
        case .feeRate:
            feeRateSatoshisPerByte += 1
        case .minimumExcessFee:
            minimumExcessFeeSatoshis -= 1
        case .maximumExcessFee:
            maximumExcessFeeSatoshis += 1
        case .requiredExcessFee:
            requiredExcessFeeSatoshis = requiredExcessFeeSatoshis
                == minimumExcessFeeSatoshis
                ? maximumExcessFeeSatoshis
                : minimumExcessFeeSatoshis
        case .transactionProfile:
            transactionProfileIdentifier = "invalid-profile"
        case nil:
            break
        }

        return try .init(
            attemptIdentifier: attemptIdentifier,
            networkGenesisHash: networkGenesisHash,
            roundIdentifier: roundIdentifier,
            expiresAt: reservationExpiration,
            componentCount: componentCount,
            feeRateSatoshisPerByte: feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: requiredExcessFeeSatoshis,
            transactionProfileIdentifier: transactionProfileIdentifier
        )
    }

    private func makeLease(
        reference: OpalFusion.Host.MosaicReservationReference? = nil,
        inputLockingScript: [UInt8] = [0x51],
        expiresAt: Date = Date(timeIntervalSince1970: 1_900_000_000)
    ) throws -> OpalFusion.Host.MosaicReservationLease {
        try .init(
            reference: reference ?? reservationReference(),
            expiresAt: expiresAt,
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: Array(
                            repeating: 0x31,
                            count: 32
                        ),
                        outpointIndex: 0,
                        amountSatoshis: 100_000,
                        lockingScriptBytes: inputLockingScript
                    )
                ],
                outputs: [
                    .init(
                        lockingScriptBytes: [0x51],
                        amountSatoshis: 99_000
                    )
                ]
            )
        )
    }

    private func reservationReference(
        finalByte: UInt8 = 0xC1
    ) -> OpalFusion.Host.MosaicReservationReference {
        .init(
            identifier: UUID(
                uuid: (
                    0, 0, 0, 0, 0, 0, 0, 0,
                    0, 0, 0, 0, 0, 0, 0, finalByte
                )
            ),
            generation: 1
        )
    }

    private enum ProbeFailure: Error {
        case publication
        case unexpectedInvocation
    }
}
