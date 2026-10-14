@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation
import Network
import Testing

extension LiveCovertTransportValidator {
    @Test("System TLS starts only inside the SOCKS tunnel and authenticates the target", arguments: ["trusted", "wrong-host", "untrusted"])
    func TLSInsideSOCKSTunnel(_ mode: String) async throws {
        let destination = try await CovertSocketTestServer.start(requiresTLS: true)
        let proxy = try await CovertSocketTestServer.start(proxyMode: .forward, tunnelPort: await destination.port)
        let anchors = mode == "untrusted" ? [] : try await LoopbackPrimaryTLSTestFixture.loadTrustAnchorCertificateDERs()
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: .init(host: "127.0.0.1", port: await proxy.port),
            tlsTrustAnchorCertificateDERs: anchors
        )
        let endpoint = Self.makeCovertEndpoint(
            host: mode == "wrong-host" ? "wrong-host.invalid" : "localhost",
            port: UInt32(await destination.port), requiresTLS: true
        )
        do {
            try await transport.prepare(Self.makePreparationPlan(endpoint: endpoint))
            if mode == "trusted" {
                let response = try await transport.perform(Self.componentRequest(endpoint: endpoint))
                #expect(response == [0x0a, 0])
                #expect(await destination.payloads.count == 1)
            } else {
                do {
                    _ = try await transport.perform(Self.componentRequest(endpoint: endpoint))
                    Issue.record("TLS accepted an untrusted or mismatched target")
                } catch let error as NWError {
                    if case .tls = error { } else { Issue.record("Expected TLS rejection, got \(error)") }
                }
                #expect(await destination.payloads.isEmpty)
            }
            #expect(await proxy.proxyRequests.map(\.host) == [endpoint.host])
            // TLS handshake record, observed only after a complete SOCKS reply.
            #expect(await proxy.firstTunnelBytes.prefix(2) == [0x16, 0x03])
        } catch {
            await transport.reset()
            await proxy.stop()
            await destination.stop()
            throw error
        }
        await transport.reset()
        await proxy.stop()
        await destination.stop()
    }
    @Test("SOCKS consumes fragmented domain and IPv6 reply addresses before framed data", arguments: [
        [UInt8](arrayLiteral: 5, 0, 0, 3, 3, 102, 111, 111, 0, 1),
        [UInt8](arrayLiteral: 5, 0, 0, 4) + [UInt8](repeating: 0, count: 16) + [0, 1]
    ])
    func variableSOCKSReplyAddress(_ reply: [UInt8]) async throws {
        try await Self.withPeer(proxyMode: .accept, host: "covert-protocol-test.invalid", proxyReply: reply) { transport, peer, endpoint in
            let response = try await transport.perform(Self.componentRequest(endpoint: endpoint))
            #expect(response == [0x0a, 0])
            #expect(await peer.payloads.count == 1)
        }
    }

    @Test("SOCKS refuses unoffered methods, authentication failure and truncated replies", arguments: [
        CovertSocketTestServer.ProxyMode.rejectMethod, .rejectAuthentication, .truncatedReply
    ])
    func rejectIncompleteOrFailedHandshake(_ mode: CovertSocketTestServer.ProxyMode) async throws {
        try await Self.withPeer(proxyMode: mode, host: "covert-protocol-test.invalid") { transport, peer, endpoint in
            await #expect(throws: (any Error).self) { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
            #expect(await peer.payloads.isEmpty)
            try await peer.waitFor(closedCount: 1)
        }
    }

    @Test("The request deadline bounds a stalled SOCKS handshake")
    func SOCKSHandshakeDeadline() async throws {
        try await Self.withPeer(proxyMode: .stall, host: "covert-protocol-test.invalid") { transport, peer, endpoint in
            await #expect(throws: OpalFusion.Runtime.LiveTransportError.covertRequestTimedOut) {
                try await transport.perform(Self.componentRequest(endpoint: endpoint, timeout: .milliseconds(100)))
            }
            try await peer.waitFor(closedCount: 1)
        }
    }

}
