// LiveCovertTransportValidator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import Testing

extension LiveCovertTransportValidator {
    @Test("macOS live covert transport rejects out-of-range endpoint ports before request execution")
    func validateOutOfRangeEndpointPortRejection() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let invalidEndpoint = Self.makeCovertEndpoint(port: UInt32(UInt16.max) + 1)
        let plan = Self.makePreparationPlan(endpoint: invalidEndpoint)
        let request = try Self.makeRequest(endpoint: invalidEndpoint)

        try await transport.prepare(plan)

        await Self.expectLiveTransportError(.malformedCovertURL) {
            try await transport.perform(request)
        }
        #expect((await executor.recordedRequests).isEmpty)
    }

    @Test("macOS live covert transport rejects empty endpoint hosts before request execution")
    func validateEmptyEndpointHostRejection() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let invalidEndpoint = Self.makeCovertEndpoint(host: "")
        let plan = Self.makePreparationPlan(endpoint: invalidEndpoint)
        let request = try Self.makeRequest(endpoint: invalidEndpoint)

        try await transport.prepare(plan)

        await Self.expectLiveTransportError(.malformedCovertURL) {
            try await transport.perform(request)
        }
        #expect((await executor.recordedRequests).isEmpty)
    }

    @Test("macOS live covert transport rejects malformed endpoint hosts before request execution")
    func validateMalformedEndpointHostRejection() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let invalidEndpoint = Self.makeCovertEndpoint(host: "-covert.example.org")
        let plan = Self.makePreparationPlan(endpoint: invalidEndpoint)
        let request = try Self.makeRequest(endpoint: invalidEndpoint)

        try await transport.prepare(plan)

        await Self.expectLiveTransportError(.malformedCovertURL) {
            try await transport.perform(request)
        }
        #expect((await executor.recordedRequests).isEmpty)
    }

    @Test("macOS live covert transport rejects malformed endpoint paths before request execution")
    func validateMalformedEndpointPathRejection() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let invalidEndpoint = Self.makeCovertEndpoint(
            entryPath: "\(PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath) "
        )
        let plan = Self.makePreparationPlan(endpoint: invalidEndpoint)
        let request = try Self.makeRequest(endpoint: invalidEndpoint)

        try await transport.prepare(plan)

        await Self.expectLiveTransportError(.malformedCovertURL) {
            try await transport.perform(request)
        }
        #expect((await executor.recordedRequests).isEmpty)
    }

    @Test("macOS live covert transport rejects endpoint paths with query delimiters before request execution")
    func validateEndpointPathQueryDelimiterRejection() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let invalidEndpoint = Self.makeCovertEndpoint(
            entryPath: "\(PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath)?round=1"
        )
        let plan = Self.makePreparationPlan(endpoint: invalidEndpoint)
        let request = try Self.makeRequest(endpoint: invalidEndpoint)

        try await transport.prepare(plan)

        await Self.expectLiveTransportError(.malformedCovertURL) {
            try await transport.perform(request)
        }
        #expect((await executor.recordedRequests).isEmpty)
    }

    @Test("macOS live covert transport rejects oversized payloads before request execution")
    func validateOversizedPayloadRejection() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let endpoint = PrimaryRuntimeTestFixtures.covertEndpointContext
        let plan = OpalFusion.Runtime.CovertPreparationPlan(
            endpoint: endpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: endpoint,
            payload: [UInt8](repeating: 0xA0, count: endpoint.maxPayloadBytes + 1),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)

        do {
            _ = try await transport.perform(request)
            Issue.record("Expected oversized covert payload to fail")
        } catch {
            #expect(
                error.localizedDescription ==
                    "Covert request payload exceeded the configured size limit"
            )
        }
        #expect((await executor.recordedRequests).isEmpty)
    }

    @Test("macOS live covert transport rejects oversized response payloads")
    func validateOversizedResponsePayloadRejection() async throws {
        let endpoint = PrimaryRuntimeTestFixtures.covertEndpointContext
        let executor = RecordedCovertRequestExecutor(
            responseData: Data(repeating: 0xA0, count: endpoint.maxPayloadBytes + 1)
        )
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let plan = OpalFusion.Runtime.CovertPreparationPlan(
            endpoint: endpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: endpoint,
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)

        do {
            _ = try await transport.perform(request)
            Issue.record("Expected oversized covert response payload to fail")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .covertResponsePayloadTooLarge)
            #expect(
                error.localizedDescription ==
                    "Covert response payload exceeded the configured size limit"
            )
        }
    }
}
