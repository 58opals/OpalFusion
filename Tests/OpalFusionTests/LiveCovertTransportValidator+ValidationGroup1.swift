// LiveCovertTransportValidator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import Testing

extension LiveCovertTransportValidator {
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

        let recordedRequests = await executor.recordedRequests
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

        let recordedRequests = await executor.recordedRequests
        guard let recordedRequest = recordedRequests.last else {
            Issue.record("Expected an HTTP covert request")
            return
        }
        #expect(recordedRequest.url?.scheme == "http")

        let proxyConfiguration = await transport.proxyConfigurationSnapshot
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

        let recordedRequests = await executor.recordedRequests
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
}
