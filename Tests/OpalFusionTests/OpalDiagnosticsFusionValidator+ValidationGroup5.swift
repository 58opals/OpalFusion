// OpalDiagnosticsFusionValidator+ValidationGroup5.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import OpalDiagnostics
import Testing

extension OpalDiagnosticsFusionValidator {
    func waitForDiagnosticRecord(
        named event: OpalDiagnostics.Event,
        matching matches: @escaping @Sendable (OpalDiagnostics.Record) -> Bool = { _ in true }
    ) async throws -> OpalDiagnostics.Record {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while true {
                if let record = findDiagnosticRecord(
                    named: event,
                    matching: matches
                ) {
                    return record
                }

                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func waitForPrimaryTransport(
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

    func waitForWrittenPayloadCount(
        _ transport: ScriptedPrimaryTransport,
        count: Int
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await transport.recordedWrittenPayloads).count < count {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }

    func waitForCovertPreparationPlan(
        _ transport: BlockingCovertTransport
    ) async throws {
        try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
            while (await transport.recordedPreparationPlans).isEmpty {
                try await Task.sleep(for: .milliseconds(10))
            }
        }
    }
}
