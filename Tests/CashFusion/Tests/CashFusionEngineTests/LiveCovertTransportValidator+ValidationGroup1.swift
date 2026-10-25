@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation
import Testing

extension LiveCovertTransportValidator {
    @Test("Covert submissions use separate retained sockets and reset closes them")
    func separateSubmissionsAndReset() async throws {
        try await Self.withPeer { transport, peer, endpoint in
            let request = try Self.componentRequest(endpoint: endpoint)
            #expect(try await transport.perform(request) == [0x0a, 0])
            #expect(try await transport.perform(request) == [0x0a, 0])
            #expect(await peer.connectionCount == 2)
            #expect(await peer.payloads == [request.payload, request.payload])
            #expect(await peer.closedConnectionCount == 0)
            await transport.reset()
            try await peer.waitFor(closedCount: 2)
            #expect(await transport.currentEndpoint == nil)
        }
    }

    @Test("Covert TLS verifies a trusted certificate and its destination hostname")
    func validateTLSExecution() async throws {
        try await Self.withPeer(requiresTLS: true, trustCertificate: true, host: "localhost") { transport, peer, endpoint in
            let response = try await transport.perform(Self.componentRequest(endpoint: endpoint))
            #expect(response == [0x0a, 0])
            #expect(await peer.payloads.count == 1)
        }
        try await Self.withPeer(requiresTLS: true, trustCertificate: true) { transport, peer, endpoint in
            await #expect(throws: (any Error).self) { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
            #expect(await peer.payloads.isEmpty) // Certificate is for localhost, not 127.0.0.1.
        }
    }

    @Test("Covert TLS never accepts an untrusted peer")
    func rejectUntrustedTLS() async throws {
        try await Self.withPeer(requiresTLS: true, host: "localhost") { transport, peer, endpoint in
            await #expect(throws: (any Error).self) { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
            #expect(await peer.payloads.isEmpty)
        }
    }

    @Test("SOCKS5 receives the remote hostname and distinct isolation credentials")
    func remoteSOCKS5Destination() async throws {
        try await Self.withPeer(proxyMode: .accept, host: "covert-protocol-test.invalid") { transport, peer, endpoint in
            let request = try Self.componentRequest(endpoint: endpoint)
            #expect(try await transport.perform(request) == [0x0a, 0])
            #expect(try await transport.perform(request) == [0x0a, 0])
            let requests = await peer.proxyRequests
            #expect(requests.map(\.host) == [endpoint.host, endpoint.host])
            #expect(requests.map(\.port) == [UInt16(endpoint.port), UInt16(endpoint.port)])
            #expect(requests.allSatisfy { $0.username == "<torS0X>0" })
            #expect(Set(requests.map(\.password)).count == 2)
        }
    }

    @Test("SOCKS5 cannot bypass the proxy for a directly reachable loopback destination")
    func noDirectProxyFallback() async throws {
        let destination = try await CovertSocketTestServer.start()
        do {
            try await Self.withPeer(proxyMode: .reject, destinationPort: UInt32(await destination.port)) { transport, proxy, endpoint in
                await #expect(throws: (any Error).self) { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
                #expect(await destination.connectionCount == 0)
                #expect(await proxy.connectionCount == 1)
            }
        } catch {
            await destination.stop()
            throw error
        }
        await destination.stop()
    }

    @Test("Remote SOCKS5 connection rejection is terminal")
    func rejectProxyFailure() async throws {
        try await Self.withPeer(proxyMode: .reject, host: "covert-protocol-test.invalid") { transport, proxy, endpoint in
            await #expect(throws: (any Error).self) { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
            #expect(await proxy.proxyRequests.count == 1)
            #expect(await proxy.payloads.isEmpty)
        }
    }

    @Test("SOCKS5 tunnels loopback and numeric destinations through the configured proxy", arguments: ["localhost", "LOCALHOST.", "foo.localhost", "127.0.0.2", "::1", "::ffff:127.0.0.1", "0.0.0.0", "::"])
    func proxyLoopbackAliases(_ host: String) async throws {
        try await Self.withPeer(proxyMode: .accept, host: host) { transport, proxy, endpoint in
            let response = try await transport.perform(Self.componentRequest(endpoint: endpoint))
            #expect(response == [0x0a, 0])
            #expect(await proxy.connectionCount == 1)
            #expect(await proxy.proxyRequests.count == 1)
        }
    }
}
