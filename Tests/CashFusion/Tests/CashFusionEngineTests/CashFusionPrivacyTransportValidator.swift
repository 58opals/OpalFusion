@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation
import Testing

@Suite(.serialized, .timeLimit(.minutes(1)))
struct CashFusionPrivacyTransportValidator {
    @Test("Primary and covert connections remotely resolve destinations with separate isolation credentials")
    func primaryAndCovertIsolation() async throws {
        let proxy = try await CovertSocketTestServer.start(reply: .silence, proxyMode: .accept)
        let tor = OpalFusion.Transport.TorSocks5Configuration(host: "127.0.0.1", port: await proxy.port)
        let primary = OpalFusion.Runtime.LivePrimaryTransport(host: "primary-test.invalid", port: 8789, torSocks5: tor)
        let covert = OpalFusion.Runtime.LiveCovertTransport(torSocks5: tor)
        let endpoint = LiveCovertTransportValidator.makeCovertEndpoint(host: "covert-test.invalid", requiresTLS: false)
        do {
            _ = try await primary.connect()
            try await primary.write(LivePrimaryTransportValidator.makeFramedClientHello())
            try await proxy.waitFor(payloadCount: 1)
            try await covert.prepare(LiveCovertTransportValidator.makePreparationPlan(endpoint: endpoint))
            // The silent peer makes the bounded covert request expire after
            // proving its independent connection and remote destination.
            await #expect(throws: OpalFusion.Runtime.LiveTransportError.covertRequestTimedOut) {
                try await covert.perform(LiveCovertTransportValidator.componentRequest(endpoint: endpoint, timeout: .milliseconds(100)))
            }
            let requests = await proxy.proxyRequests
            #expect(requests.map(\.host) == ["primary-test.invalid", "covert-test.invalid"])
            #expect(requests.map(\.port) == [8789, UInt16(endpoint.port)])
            #expect(requests.allSatisfy { $0.username == "<torS0X>0" })
            #expect(Set(requests.map(\.password)).count == 2)
            #expect(await proxy.payloads.count == 2)
        } catch {
            await primary.close()
            await covert.reset()
            await proxy.stop()
            throw error
        }
        await primary.close()
        await covert.reset()
        await proxy.stop()
    }

    @Test("Closing primary transport cancels a stalled SOCKS handshake")
    func primarySOCKSCancellation() async throws {
        let proxy = try await CovertSocketTestServer.start(proxyMode: .stall)
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "primary-test.invalid", port: 8789,
            torSocks5: .init(host: "127.0.0.1", port: await proxy.port)
        )
        let task = Task { try await transport.connect() }
        do {
            try await proxy.waitFor(connectionCount: 1)
            await transport.close()
            await #expect(throws: (any Error).self) { try await task.value }
            try await proxy.waitFor(closedCount: 1)
            #expect(await proxy.payloads.isEmpty)
        } catch {
            task.cancel()
            await transport.close()
            await proxy.stop()
            throw error
        }
        await proxy.stop()
    }

    @Test("Primary TLS and its protocol exchange stay inside SOCKS", arguments: [false, true])
    func primaryTLSInsideSOCKS(trustCertificate: Bool) async throws {
        let destination = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let proxy = try await CovertSocketTestServer.start(proxyMode: .forward, tunnelPort: await destination.port)
        let anchors = trustCertificate ? try await LoopbackPrimaryTLSTestFixture.loadTrustAnchorCertificateDERs() : []
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "localhost", port: await destination.port, requiresTLS: true,
            torSocks5: .init(host: "127.0.0.1", port: await proxy.port),
            tlsTrustAnchorCertificateDERs: anchors
        )
        do {
            if trustCertificate {
                _ = try await transport.connect()
                try await transport.write(LivePrimaryTransportValidator.makeFramedClientHello())
                #expect(try await destination.readNextClientMessage() == .clientHello(PrimaryRuntimeTestFixtures.clientHello))
            } else {
                await #expect(throws: (any Error).self) { try await transport.connect() }
                #expect(await destination.recordedClientMessages.isEmpty)
            }
            #expect(await proxy.proxyRequests.map(\.host) == ["localhost"])
            #expect(await proxy.firstTunnelBytes.prefix(2) == [0x16, 0x03])
        } catch {
            await transport.close()
            await proxy.stop()
            await destination.stop()
            throw error
        }
        await transport.close()
        await proxy.stop()
        await destination.stop()
    }

    @Test("A session without anonymous transport fails before building transports")
    func missingProxyRejectsBeforeTransportFactories() async {
        let factories = SessionTransportFactoryRecorder()
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "fusion.example.org",
            coordinatorPort: 8_789,
            covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel
        )
        let session = OpalFusion.Client.Session(
            configuration: configuration,
            joinPools: PrimaryRuntimeTestFixtures.joinPools,
            hostParticipantReservationSource: HostParticipantReservationSourceAdapter(
                participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
            ),
            hostTransactionAssembler: HostTransactionAssemblerAdapter(
                finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
            ),
            primaryTransportFactory: { await factories.makePrimary() },
            covertTransportFactory: { await factories.makeCovert() }
        )
        await session.start()
        let snapshot = await session.currentSnapshot
        #expect(snapshot.lastError == .invalidConfiguration)
        #expect(snapshot.state.isConnected == false)
        #expect(await factories.primaryTransportCount == 0)
        await session.stop()
    }

    @Test("Covert preparation cannot silently select direct transport")
    func missingProxyRejectsCovertPreparation() async {
        let transport = OpalFusion.Runtime.LiveCovertTransport(torSocks5: nil)
        await #expect(throws: (any Error).self) {
            try await transport.prepare(LiveCovertTransportValidator.makePreparationPlan(
                endpoint: LiveCovertTransportValidator.makeCovertEndpoint()
            ))
        }
        #expect(await transport.currentEndpoint == nil)
    }

    @Test("Production primary factories cannot bypass a rejecting proxy", arguments: [false, true])
    func primaryCannotBypassRejectingProxy(usePublicSession: Bool) async throws {
        let destination = try await CovertSocketTestServer.start(reply: .silence)
        let proxy = try await CovertSocketTestServer.start(proxyMode: .reject)
        let configuration = OpalFusion.Client.Configuration(
            coordinatorHost: "127.0.0.1",
            coordinatorPort: await destination.port,
            covertChannel: PrimaryRuntimeTestFixtures.configuration.covertChannel,
            torSocks5: .init(host: "127.0.0.1", port: await proxy.port)
        )
        let source = HostParticipantReservationSourceAdapter(
            participantInputs: [PrimaryRuntimeTestFixtures.participantInput]
        )
        let assembler = HostTransactionAssemblerAdapter(
            finalizedTransaction: PrimaryRuntimeTestFixtures.finalizedTransaction
        )
        if usePublicSession {
            let session = OpalFusion.Client.Session(
                configuration: configuration,
                joinPools: PrimaryRuntimeTestFixtures.joinPools,
                hostParticipantReservationSource: source,
                hostTransactionAssembler: assembler
            )
            await session.start()
            #expect(await session.currentSnapshot.lastError == .transportUnavailable)
            await session.stop()
        } else {
            let driver = OpalFusion.Runtime.LiveRuntimeDriver(
                configuration: configuration,
                joinPools: PrimaryRuntimeTestFixtures.joinPools,
                participantReservationSource: source,
                transactionAssembler: assembler
            )
            await driver.start()
            #expect(await driver.currentSnapshot.lastError == .transportUnavailable)
            await driver.stop()
        }
        #expect(await destination.connectionCount == 0)
        #expect(await proxy.connectionCount == 1)
        await proxy.stop()
        await destination.stop()
    }
}
