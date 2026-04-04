// LiveCovertTransportValidator.swift

@testable import OpalFusion
import Foundation
import Testing

struct LiveCovertTransportValidator {
    @Test("Live covert transport prepares endpoint state and executes HTTPS requests")
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

    @Test("Live covert transport switches between HTTP and HTTPS and applies SOCKS5 proxy settings")
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

        let insecureEndpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: false,
            entryPath: PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath,
            maxPayloadBytes: PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes,
            requestTimeoutMilliseconds: PrimaryRuntimeTestFixtures.covertEndpointContext.requestTimeoutMilliseconds,
            connectTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.connectTimeout,
            connectWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.connectWindow,
            submitTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.submitTimeout,
            submitWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.submitWindow,
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )
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
}
