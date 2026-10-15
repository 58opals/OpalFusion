@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation
import Network
import Testing

@Suite(.timeLimit(.minutes(1)))
struct LiveCovertSocketValidator {
    @Test("Live covert submissions use Electron Cash socket framing, not HTTP")
    func exchangeOfficialFrame() async throws {
        let server = try await CovertSocketTestServer.start(proxyMode: .accept)
        let endpoint = LiveCovertTransportValidator.makeCovertEndpoint(
            host: "127.0.0.1", port: UInt32(await server.port), requiresTLS: false
        )
        let transport = OpalFusion.Runtime.LiveCovertTransport(
            torSocks5: .init(host: "127.0.0.1", port: await server.port)
        )
        do {
            try await transport.prepare(LiveCovertTransportValidator.makePreparationPlan(endpoint: endpoint))
            let payload = try PrimaryRuntimeTestFixtures.encodeCovertMessagePayload(
                PrimaryRuntimeTestFixtures.covertComponentMessage
            )
            let request = OpalFusion.Runtime.CovertRequest(
                endpoint: endpoint, payload: payload,
                startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
                deadline: PrimaryRuntimeTestFixtures.instant(1_002)
            )
            let response = try await transport.perform(request)
            #expect(response == [0x0a, 0x00]) // CovertResponse.ok, independently encoded.
            #expect(await server.payloads == [payload])
        } catch {
            Issue.record("Framed covert exchange failed: \(error); peer first bytes: \(await server.firstBytes)")
        }
        await transport.reset()
        await server.stop()
    }
}
