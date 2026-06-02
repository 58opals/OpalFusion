// ClientSessionValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct ClientSessionValidator {


































}

extension ClientSessionValidator {
    static let fastReconnectPolicy = OpalFusion.Client.ReconnectPolicy(
        initialDelay: .milliseconds(10),
        maximumDelay: .milliseconds(10),
        multiplier: 1,
        maximumAttempts: 3
    )

    static func waitForObservedSnapshot(
        _ stateObserver: RecordedClientStateObserver,
        matching predicate: @escaping @Sendable (
            OpalFusion.Client.Session.Snapshot
        ) -> Bool
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                if let snapshot = (await stateObserver.recordedSnapshots).last(where: predicate) {
                    return snapshot
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func waitForSessionSnapshot(
        _ session: OpalFusion.Client.Session,
        matching predicate: @escaping @Sendable (
            OpalFusion.Client.Session.Snapshot
        ) -> Bool
    ) async throws -> OpalFusion.Client.Session.Snapshot {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                let snapshot = await session.currentSnapshot
                if predicate(snapshot) {
                    return snapshot
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func waitForPrimaryTransport(
        _ transportFactories: SessionTransportFactoryRecorder,
        at index: Int
    ) async throws -> ScriptedPrimaryTransport {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                if let transport = await transportFactories.primaryTransport(at: index) {
                    return transport
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func waitForWrittenPayloadCount(
        _ transport: ScriptedPrimaryTransport,
        count: Int
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await transport.recordedWrittenPayloads).count < count {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    static func advanceToStartRound(
        _ transport: ScriptedPrimaryTransport,
        nowProvider: ScriptedInstantClock,
        covertTransport: ScriptedCovertTransport
    ) async throws {
        try await waitForWrittenPayloadCount(transport, count: 1)

        await nowProvider.update(unixSeconds: 996)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello)
            )
        )
        try await waitForWrittenPayloadCount(transport, count: 2)

        await nowProvider.update(unixSeconds: 1_000)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .fusionBegin(PrimaryRuntimeTestFixtures.fusionBegin)
            )
        )
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await covertTransport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }

        await nowProvider.update(unixSeconds: 1_030)
        await transport.yieldInboundBytes(
            try PrimaryRuntimeTestFixtures.encodeServerFrame(
                .startRound(PrimaryRuntimeTestFixtures.startRound)
            )
        )
    }
}
