// MosaicPrivateAlphaRuntimeRecoveryValidator.swift

import Foundation
import Testing
@_spi(MosaicPrivateAlpha) import OpalFusion

@Suite("Mosaic private-alpha exact runtime recovery", .serialized)
struct MosaicPrivateAlphaRuntimeRecoveryValidator {
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    @Test("Persist and restore one exact fresh binding")
    func persistAndRestoreFreshBinding() async throws {
        let binding = try makeBinding(seed: 0x10)
        let fresh = try Runtime.createFreshAttempt(
            boundTo: binding,
            discoveryEpochStartUnixSeconds: 1_800_000_000
        )
        let owner = try Runtime.Owner(claiming: fresh)
        let initial = try transition(from: await owner.nextStep())
        #expect(initial.expectedSnapshot == nil)
        #expect(initial.binding == binding)

        let next = try await owner.acknowledgePersistence(
            initial,
            exactReadback: initial.replacementSnapshot
        )
        #expect(next == .awaitingInput(.discovery))

        let loaded = try Runtime.loadRecovery(
            from: initial.replacementSnapshot,
            expectedBinding: binding
        )
        #expect(loaded.binding == binding)
        let recovered = try Runtime.Owner(claiming: loaded)
        guard case let .recover(.resumePrivateDeployment(continuation)) =
            try await recovered.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(continuation.binding == binding)
        #expect(continuation.phase == .discovery)
    }

    @Test("Reject partial, trailing, and differently bound recovery bytes")
    func rejectMalformedAndMismatchedRecovery() async throws {
        let binding = try makeBinding(seed: 0x20)
        let fresh = try Runtime.createFreshAttempt(
            boundTo: binding,
            discoveryEpochStartUnixSeconds: 1_800_000_000
        )
        let owner = try Runtime.Owner(claiming: fresh)
        let initial = try transition(from: await owner.nextStep())

        #expect(throws: Runtime.Failure.partialRecoverySnapshot) {
            _ = try Runtime.loadRecovery(
                from: initial.replacementSnapshot.dropLast(),
                expectedBinding: binding
            )
        }
        #expect(throws: Runtime.Failure.nonCanonicalRecoverySnapshot) {
            _ = try Runtime.loadRecovery(
                from: initial.replacementSnapshot + Data([0]),
                expectedBinding: binding
            )
        }
        #expect(throws: Runtime.Failure.recoveryBindingMismatch) {
            _ = try Runtime.loadRecovery(
                from: initial.replacementSnapshot,
                expectedBinding: makeBinding(seed: 0x30)
            )
        }
    }

    @Test("Require exact durable readback before exposing formation")
    func requireExactDurableReadback() async throws {
        let fresh = try Runtime.createFreshAttempt(
            boundTo: makeBinding(seed: 0x40),
            discoveryEpochStartUnixSeconds: 1_800_000_000
        )
        let owner = try Runtime.Owner(claiming: fresh)
        let initial = try transition(from: await owner.nextStep())
        var altered = initial.replacementSnapshot
        altered[altered.startIndex] ^= 0x01

        await #expect(throws: Runtime.Failure.exactReadbackMismatch) {
            _ = try await owner.acknowledgePersistence(
                initial,
                exactReadback: altered
            )
        }
        #expect(try await owner.nextStep() == .persist(initial))
    }

    private func transition(from step: Runtime.Step) throws
        -> Runtime.RecoveryTransition {
        guard case let .persist(transition) = step else {
            throw Runtime.Failure.invalidStateTransition
        }
        return transition
    }

    private func makeBinding(seed: UInt8) throws -> Runtime.Binding {
        try .init(
            attemptIdentifier: Data(repeating: seed, count: 32),
            generationIdentifier: Data(repeating: seed &+ 1, count: 32),
            materialIdentifier: Data(repeating: seed &+ 2, count: 32)
        )
    }
}
