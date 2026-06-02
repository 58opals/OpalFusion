// LiveCovertTransportValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct LiveCovertTransportValidator {










}

extension LiveCovertTransportValidator {
    static func expectLiveTransportError(
        _ expectedError: OpalFusion.Runtime.LiveTransportError,
        from operation: () async throws -> [UInt8]
    ) async {
        await #expect(throws: expectedError) {
            try await operation()
        }
    }

    static func makeCovertEndpoint(
        host: String = PrimaryRuntimeTestFixtures.covertEndpointContext.host,
        port: UInt32 = PrimaryRuntimeTestFixtures.covertEndpointContext.port,
        requiresTLS: Bool? = PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
        entryPath: String = PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath
    ) -> OpalFusion.Runtime.CovertEndpointContext {
        let baseEndpoint = PrimaryRuntimeTestFixtures.covertEndpointContext
        return .init(
            roundIdentifier: baseEndpoint.roundIdentifier,
            host: host,
            port: port,
            requiresTLS: requiresTLS,
            entryPath: entryPath,
            maxPayloadBytes: baseEndpoint.maxPayloadBytes,
            requestTimeoutMilliseconds: baseEndpoint.requestTimeoutMilliseconds,
            connectTimeout: baseEndpoint.connectTimeout,
            connectWindow: baseEndpoint.connectWindow,
            submitTimeout: baseEndpoint.submitTimeout,
            submitWindow: baseEndpoint.submitWindow,
            spareConnectionCount: baseEndpoint.spareConnectionCount
        )
    }

    static func makePreparationPlan(
        endpoint: OpalFusion.Runtime.CovertEndpointContext
    ) -> OpalFusion.Runtime.CovertPreparationPlan {
        .init(
            endpoint: endpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
    }

    static func makeRequest(
        endpoint: OpalFusion.Runtime.CovertEndpointContext
    ) throws -> OpalFusion.Runtime.CovertRequest {
        .init(
            endpoint: endpoint,
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )
    }
}
