// LiveCovertTransportValidator.swift

@testable import OpalFusion
import Foundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LiveCovertTransportValidator { }

extension LiveCovertTransportValidator {
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


}

extension LiveCovertTransportValidator {
    static func componentRequest(endpoint: OpalFusion.Runtime.CovertEndpointContext, timeout: Duration = .seconds(2)) throws -> OpalFusion.Runtime.CovertRequest {
        request(endpoint: endpoint, payload: try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(PrimaryRuntimeTestFixtures.covertComponentMessage), timeout: timeout)
    }

    static func request(endpoint: OpalFusion.Runtime.CovertEndpointContext, payload: [UInt8], timeout: Duration = .seconds(2)) -> OpalFusion.Runtime.CovertRequest {
        let start = PrimaryRuntimeTestFixtures.instant(1_000)
        return .init(endpoint: endpoint, payload: payload, startedAt: start, deadline: start.advanced(by: timeout))
    }

    static func withPeer(
        reply: CovertSocketTestServer.Reply = .acknowledgement,
        requiresTLS: Bool = false,
        trustCertificate: Bool = false,
        proxyMode: CovertSocketTestServer.ProxyMode = .disabled,
        host: String = "127.0.0.1",
        destinationPort: UInt32? = nil,
        proxyReply: [UInt8]? = nil,
        operation: @Sendable (OpalFusion.Runtime.LiveCovertTransport, CovertSocketTestServer, OpalFusion.Runtime.CovertEndpointContext) async throws -> Void
    ) async throws {
        let server = try await CovertSocketTestServer.start(reply: reply, requiresTLS: requiresTLS, proxyMode: proxyMode, proxyReply: proxyReply)
        let proxy: OpalFusion.Transport.TorSocks5Configuration? = proxyMode == .disabled ? nil : .init(host: "127.0.0.1", port: await server.port)
        let anchors = trustCertificate ? try await LoopbackPrimaryTLSTestFixture.loadTrustAnchorCertificateDERs() : []
        let transport = OpalFusion.Runtime.LiveCovertTransport(torSocks5: proxy, tlsTrustAnchorCertificateDERs: anchors)
        let serverPort = await server.port
        let endpoint = makeCovertEndpoint(host: host, port: destinationPort ?? UInt32(serverPort), requiresTLS: requiresTLS)
        do {
            try await transport.prepare(makePreparationPlan(endpoint: endpoint))
            try await operation(transport, server, endpoint)
        } catch {
            await transport.reset()
            await server.stop()
            throw error
        }
        await transport.reset()
        await server.stop()
    }
}
