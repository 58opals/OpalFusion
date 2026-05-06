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

    @Test("macOS live covert transport rejects responses without HTTP metadata")
    func validateNonHTTPResponseRejection() async throws {
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: nil,
            requestExecutor: { _, request in
                guard let url = request.url else {
                    throw LiveRuntimeTestSupportError.inboundStreamClosed
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

        do {
            _ = try await transport.perform(request)
            Issue.record("Expected non-HTTP covert response to fail")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .invalidHTTPResponse)
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
        let invalidEndpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: UInt32(UInt16.max) + 1,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
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
            endpoint: invalidEndpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: invalidEndpoint,
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)

        do {
            _ = try await transport.perform(request)
            Issue.record("Expected out-of-range covert port to fail")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .malformedCovertURL)
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
        let invalidEndpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: "",
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
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
            endpoint: invalidEndpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: invalidEndpoint,
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)

        do {
            _ = try await transport.perform(request)
            Issue.record("Expected empty covert host to fail")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .malformedCovertURL)
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
        let invalidEndpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: "-covert.example.org",
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
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
            endpoint: invalidEndpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: invalidEndpoint,
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)

        do {
            _ = try await transport.perform(request)
            Issue.record("Expected malformed covert host to fail")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .malformedCovertURL)
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
        let invalidEndpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
            entryPath: "\(PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath) ",
            maxPayloadBytes: PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes,
            requestTimeoutMilliseconds: PrimaryRuntimeTestFixtures.covertEndpointContext.requestTimeoutMilliseconds,
            connectTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.connectTimeout,
            connectWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.connectWindow,
            submitTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.submitTimeout,
            submitWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.submitWindow,
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )
        let plan = OpalFusion.Runtime.CovertPreparationPlan(
            endpoint: invalidEndpoint,
            startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
            deadline: PrimaryRuntimeTestFixtures.instant(1_015)
        )
        let request = OpalFusion.Runtime.CovertRequest(
            endpoint: invalidEndpoint,
            payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.pingMessage
            ),
            startedAt: PrimaryRuntimeTestFixtures.instant(1_001),
            deadline: PrimaryRuntimeTestFixtures.instant(1_004)
        )

        try await transport.prepare(plan)

        do {
            _ = try await transport.perform(request)
            Issue.record("Expected malformed covert endpoint path to fail")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .malformedCovertURL)
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
