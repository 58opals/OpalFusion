@testable import OpalFusion
import Foundation
import Testing

extension LiveCovertTransportValidator {
    @Test("Covert preparation rejects invalid endpoints before opening sockets", arguments: ["", "-covert.example.org"])
    func invalidHost(_ host: String) async throws {
        let transport = OpalFusion.Runtime.LiveCovertTransport(torSocks5: nil)
        await #expect(throws: OpalFusion.Runtime.LiveTransportError.malformedCovertEndpoint) {
            try await transport.prepare(Self.makePreparationPlan(endpoint: Self.makeCovertEndpoint(host: host)))
        }
    }

    @Test("Covert preparation rejects invalid ports", arguments: [UInt32(0), UInt32(UInt16.max) + 1])
    func invalidPort(_ port: UInt32) async throws {
        let transport = OpalFusion.Runtime.LiveCovertTransport(torSocks5: nil)
        await #expect(throws: OpalFusion.Runtime.LiveTransportError.malformedCovertEndpoint) {
            try await transport.prepare(Self.makePreparationPlan(endpoint: Self.makeCovertEndpoint(port: port)))
        }
    }

    @Test("Oversized covert payloads are rejected before opening a socket")
    func oversizedRequest() async throws {
        try await Self.withPeer { transport, peer, endpoint in
            let request = Self.request(endpoint: endpoint, payload: [UInt8](repeating: 0, count: endpoint.maxPayloadBytes + 1))
            await #expect(throws: OpalFusion.Runtime.LiveTransportError.covertPayloadTooLarge) { try await transport.perform(request) }
            #expect(await peer.connectionCount == 0)
        }
    }

    @Test("Malformed and truncated covert frames fail without accepting a response", arguments: [CovertSocketTestServer.Reply.badMagic, .truncated])
    func invalidResponse(_ reply: CovertSocketTestServer.Reply) async throws {
        try await Self.withPeer(reply: reply) { transport, peer, endpoint in
            await #expect(throws: (any Error).self) { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
            try await peer.waitFor(closedCount: 1)
        }
    }

    @Test("Oversized covert response headers are rejected before their bodies arrive")
    func oversizedResponse() async throws {
        try await Self.withPeer(reply: .oversized(PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes + 1)) { transport, peer, endpoint in
            await #expect(throws: OpalFusion.Runtime.LiveTransportError.covertResponsePayloadTooLarge) {
                try await transport.perform(Self.componentRequest(endpoint: endpoint))
            }
            try await peer.waitFor(closedCount: 1)
        }
    }

    @Test("Covert request deadline closes a silent peer connection")
    func requestDeadline() async throws {
        try await Self.withPeer(reply: .silence) { transport, peer, endpoint in
            await #expect(throws: OpalFusion.Runtime.LiveTransportError.covertRequestTimedOut) {
                try await transport.perform(Self.componentRequest(endpoint: endpoint, timeout: .milliseconds(100)))
            }
            try await peer.waitFor(closedCount: 1)
        }
    }

    @Test("Cancelling a pending SOCKS handshake closes its socket")
    func cancelDuringConnect() async throws {
        try await Self.withPeer(proxyMode: .stall, host: "covert-protocol-test.invalid") { transport, peer, endpoint in
            let task = Task { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
            try await peer.waitFor(connectionCount: 1)
            task.cancel()
            let result = await task.result
            if case .success = result { Issue.record("Cancelled connection succeeded") }
            try await peer.waitFor(closedCount: 1)
        }
    }

    @Test("Reset cancels an old response without closing a newly prepared generation")
    func resetDuringResponse() async throws {
        try await Self.withPeer(reply: .silence) { transport, peer, endpoint in
            let task = Task { try await transport.perform(Self.componentRequest(endpoint: endpoint)) }
            try await peer.waitFor(payloadCount: 1)
            await transport.reset()
            let nextPeer = try await CovertSocketTestServer.start()
            let nextEndpoint = Self.makeCovertEndpoint(host: "127.0.0.1", port: UInt32(await nextPeer.port), requiresTLS: false)
            do {
                try await transport.prepare(Self.makePreparationPlan(endpoint: nextEndpoint))
                let result = await task.result
                if case .success = result { Issue.record("Reset request succeeded") }
                #expect(try await transport.perform(Self.componentRequest(endpoint: nextEndpoint)) == [0x0a, 0])
                #expect(await transport.currentEndpoint == nextEndpoint)
                try await peer.waitFor(closedCount: 1)
            } catch {
                await nextPeer.stop()
                throw error
            }
            await nextPeer.stop()
        }
    }
}
