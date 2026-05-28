// LiveCovertTransportValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct LiveCovertTransportValidator {
    @Test("macOS live covert transport prepares endpoint state and executes HTTPS requests")
    func validateTLSExecution() async throws {
        let executor = RecordedCovertRequestExecutor(
            responseData: Data(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            )
        )
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let expectedResponseBytes = try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
            PrimaryRuntimeTestFixtures.acknowledgement
        )
        let expectedRequestPayload = try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
            PrimaryRuntimeTestFixtures.covertComponentMessage
        )

        try await transport.prepare(
            PrimaryRuntimeTestFixtures.expectedPreparationPlan(startedAt: 1_000)
        )
        let responseBytes = try await transport.perform(
            try PrimaryRuntimeTestFixtures.expectedRequest(
                for: PrimaryRuntimeTestFixtures.covertComponentMessage,
                startedAt: 1_001
            )
        )

        #expect(responseBytes == expectedResponseBytes)
        #expect(await transport.currentEndpoint == PrimaryRuntimeTestFixtures.covertEndpointContext)

        let recordedRequests = await executor.recordedRequests()
        guard let request = recordedRequests.last else {
            Issue.record("Expected a recorded covert request")
            return
        }
        #expect(request.url?.scheme == "https")
        #expect(request.url?.host == PrimaryRuntimeTestFixtures.covertEndpointContext.host)
        #expect(request.url?.port == Int(PrimaryRuntimeTestFixtures.covertEndpointContext.port))
        #expect(request.url?.path == PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath)
        #expect(request.httpMethod == "POST")
        #expect([UInt8](request.httpBody ?? Data()) == expectedRequestPayload)
    }

    @Test("macOS live covert transport switches between HTTP and HTTPS and applies SOCKS5 proxy settings")
    func validateURLAndProxyConfiguration() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let torSocks5 = OpalFusion.Transport.TorSocks5Configuration(
            host: "127.0.0.1",
            port: 9_050
        )
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: torSocks5,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )

        let insecureEndpoint = Self.makeCovertEndpoint(requiresTLS: false)
        let plan = OpalFusion.Runtime.CovertPreparationPlan(
            endpoint: insecureEndpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: insecureEndpoint,
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)
        _ = try await transport.perform(request)

        let recordedRequests = await executor.recordedRequests()
        guard let recordedRequest = recordedRequests.last else {
            Issue.record("Expected an HTTP covert request")
            return
        }
        #expect(recordedRequest.url?.scheme == "http")

        let proxyConfiguration = await transport.proxyConfigurationSnapshot()
        #expect(proxyConfiguration.socksEnabled)
        #expect(proxyConfiguration.proxyHost == torSocks5.host)
        #expect(proxyConfiguration.proxyPort == Int(torSocks5.port))
    }

    @Test("macOS live covert transport builds requests for raw IPv6 endpoint hosts")
    func validateRawIPv6EndpointHostExecution() async throws {
        let executor = RecordedCovertRequestExecutor(responseData: Data())
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { session, request in
                try await executor.execute(session: session, request: request)
            }
        )
        let endpoint = Self.makeCovertEndpoint(host: "::1")
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
        _ = try await transport.perform(request)

        let recordedRequests = await executor.recordedRequests()
        let recordedRequest = try #require(recordedRequests.last)
        #expect(recordedRequest.url?.host == "::1")
    }

    @Test("macOS live covert transport rejects responses without HTTP metadata")
    func validateNonHTTPResponseRejection() async throws {
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { _, request in
                guard let url = request.url else {
                    throw LiveRuntimeTestHarnessError.inboundStreamClosed
                }
                return (
                    Data(),
                    URLResponse(
                        url: url,
                        mimeType: nil,
                        expectedContentLength: 0,
                        textEncodingName: nil
                    )
                )
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
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)

        await Self.expectLiveTransportError(.invalidHTTPResponse) {
            try await transport.perform(request)
        }
    }

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
        #expect(await executor.recordedRequests().isEmpty)
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
        #expect(await executor.recordedRequests().isEmpty)
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
        #expect(await executor.recordedRequests().isEmpty)
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
        #expect(await executor.recordedRequests().isEmpty)
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
        #expect(await executor.recordedRequests().isEmpty)
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
        #expect(await executor.recordedRequests().isEmpty)
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

private extension LiveCovertTransportValidator {
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
