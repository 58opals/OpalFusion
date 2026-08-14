// MosaicMainnetAlphaReservationCoordinatorDependencyValidator.swift

import Foundation
import Synchronization
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha reservation dependency ownership")
struct MosaicMainnetAlphaReservationCoordinatorDependencyValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Coordinator = Alpha.ReservationCoordinator
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias Host = OpalFusion.Host
    typealias Session = Alpha.RuntimeSession

    private struct RejectingPreviousOutputSource:
        Host.MosaicPreviousOutputSource
    {
        func resolvePreviousOutputs(
            for _: [Host.MosaicPreviousOutputRequest]
        ) async throws -> [Host.MosaicPreviousOutput] {
            throw ProbeFailure.unexpectedInvocation
        }
    }

    private final class InvocationProbe: Sendable {
        enum Invocation: Hashable, Sendable {
            case material
            case playerCommit
            case anonymousComponents
            case preSignAcknowledgement
            case localSignatures
        }

        private let counts = Mutex<[Invocation: Int]>([:])
        private let receivedLeases = Mutex<[Host.MosaicReservationLease]>([])

        func record(
            _ invocation: Invocation,
            lease: Host.MosaicReservationLease? = nil
        ) {
            counts.withLock { $0[invocation, default: 0] += 1 }
            if let lease {
                receivedLeases.withLock { $0.append(lease) }
            }
        }

        func count(_ invocation: Invocation) -> Int {
            counts.withLock { $0[invocation, default: 0] }
        }

        var leases: [Host.MosaicReservationLease] {
            receivedLeases.withLock { $0 }
        }
    }

    @Test("Accept exact material and actual leases")
    func acceptExactLease() throws {
        let lease = try makeLease()
        try Alpha.ReservationMaterialLeaseValidator.validate(
            actualLease: lease,
            materialLease: lease
        )
    }

    @Test("Reject a foreign material lease reference")
    func rejectForeignReference() throws {
        let actualLease = try makeLease()
        let materialLease = try makeLease(referenceFinalByte: 0xD2)
        #expect(throws: Alpha.ReservationMaterialLeaseValidator.ValidationError.mismatch) {
            try Alpha.ReservationMaterialLeaseValidator.validate(
                actualLease: actualLease,
                materialLease: materialLease
            )
        }
    }

    @Test("Reject changed material contents under the same reference and expiry")
    func rejectChangedParticipantReservation() throws {
        let actualLease = try makeLease()
        let materialLease = try makeLease(inputHashByte: 0x32)
        #expect(throws: Alpha.ReservationMaterialLeaseValidator.ValidationError.mismatch) {
            try Alpha.ReservationMaterialLeaseValidator.validate(
                actualLease: actualLease,
                materialLease: materialLease
            )
        }
    }

    @Test("Invoke material construction unconditionally and release its exact lease on failure")
    func releaseExactLeaseAfterMaterialFailure() async throws {
        let probe = InvocationProbe()
        let harness = try makeCoordinator(probe: probe)
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(probe.count(.material) == 1)
        #expect(probe.leases == [harness.lease])
        #expect(probe.count(.playerCommit) == 0)
        #expect(probe.count(.anonymousComponents) == 0)
        #expect(probe.count(.preSignAcknowledgement) == 0)
        #expect(probe.count(.localSignatures) == 0)
        #expect(await harness.host.signingRequests.isEmpty)
        #expect(await harness.host.completeCommits.isEmpty)
        #expect(await harness.host.legacyCommitCount == 0)
        #expect(await harness.host.releasedReferences == [harness.lease.reference])
        #expect(
            await harness.coordinator.state
                == .terminal(.failed(.localMaterialInvalid))
        )
    }

    @Test("Require exact-reference recovery when material-failure release fails")
    func requireRecoveryAfterMaterialFailureReleaseFailure() async throws {
        let probe = InvocationProbe()
        let harness = try makeCoordinator(probe: probe)
        await harness.host.failRelease()
        await harness.coordinator.start()
        try await submitManifest(harness)
        await harness.coordinator.waitForTermination()

        #expect(probe.count(.material) == 1)
        #expect(probe.leases == [harness.lease])
        #expect(probe.count(.playerCommit) == 0)
        #expect(probe.count(.anonymousComponents) == 0)
        #expect(probe.count(.preSignAcknowledgement) == 0)
        #expect(probe.count(.localSignatures) == 0)
        #expect(await harness.host.signingRequests.isEmpty)
        #expect(await harness.host.completeCommits.isEmpty)
        #expect(await harness.host.legacyCommitCount == 0)
        #expect(await harness.host.releasedReferences == [harness.lease.reference])
        #expect(
            await harness.coordinator.state == .recoveryRequired(
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
    }

    private struct Harness {
        let admission: Fixture.Harness
        let lease: Host.MosaicReservationLease
        let host: MosaicRuntimeCoordinatorHostProbe
        let coordinator: Coordinator
    }

    private func makeCoordinator(probe: InvocationProbe) throws -> Harness {
        let admission = try Fixture.makeHarness(localRole: .contributor)
        let session = try Session(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: admission.election
            ),
            attemptIdentifier: admission.attemptIdentifier,
            generationIdentifier: admission.generationIdentifier,
            materialIdentifier: admission.materialIdentifier,
            localControlIdentity: admission.localControlIdentity,
            proposalValidation: admission.proposalValidation
        )
        let lease = try makeLease()
        let host = MosaicRuntimeCoordinatorHostProbe(
            lease: lease,
            finalizedTransaction: .init(signedFusionTransactionBytes: [0x01])
        )
        let execution = Coordinator.ExecutionDependencies(
            transactionHost: host,
            previousOutputSource: RejectingPreviousOutputSource(),
            makeLocalContributionMaterial: { _, receivedLease in
                probe.record(.material, lease: receivedLease)
                throw ProbeFailure.material
            },
            publishPlayerCommit: { _ in probe.record(.playerCommit) },
            publishAnonymousComponents: { _ in
                probe.record(.anonymousComponents)
            },
            publishPreSignAcknowledgement: { _ in
                probe.record(.preSignAcknowledgement)
            },
            publishLocalBCHSignatures: { _ in
                probe.record(.localSignatures)
            }
        )
        let coordinator = try Coordinator(
            runtimeSession: session,
            dependencies: .init(
                execution: execution,
                expectedReservationExpiration: lease.expiresAt,
                makeReservationRequest: { eligibility in
                    try MosaicMainnetAlphaExecutionFixtures.reservationRequest(
                        for: eligibility,
                        expiresAt: lease.expiresAt
                    )
                }
            )
        )
        return .init(
            admission: admission,
            lease: lease,
            host: host,
            coordinator: coordinator
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
        #expect(await harness.coordinator.submitControl(run.reservation))
        for fragment in run.fragments {
            #expect(await harness.coordinator.submitControl(fragment))
        }
    }

    private func makeLease(
        referenceFinalByte: UInt8 = 0xD1,
        inputHashByte: UInt8 = 0x31
    ) throws -> Host.MosaicReservationLease {
        try .init(
            reference: .init(
                identifier: UUID(
                    uuid: (
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0, 0, 0, 0, 0, 0, 0, referenceFinalByte
                    )
                ),
                generation: 1
            ),
            expiresAt: Date(timeIntervalSince1970: 1_900_000_000),
            participantReservation: .init(
                inputs: [
                    .init(
                        outpointTransactionHashBytes: Array(
                            repeating: inputHashByte,
                            count: 32
                        ),
                        outpointIndex: 0,
                        amountSatoshis: 100_000,
                        lockingScriptBytes: [0x51]
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

    private enum ProbeFailure: Error {
        case material
        case unexpectedInvocation
    }
}
