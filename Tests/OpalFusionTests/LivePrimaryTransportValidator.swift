// LivePrimaryTransportValidator.swift

@testable import OpalFusion
import Testing

struct LivePrimaryTransportValidator {
    @Test("Live primary transport writes framed client messages to a loopback coordinator")
    func validateLoopbackWritePath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: await coordinator.port
        )
        _ = try await transport.connect()

        let payload = try OpalFusion.Wire.PrimaryMessageEncoder().encode(
            .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )
        let framedBytes = try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: PrimaryRuntimeTestFixtures.baseline.framing
        )
        .encode(payload: payload)

        try await transport.write(framedBytes)

        let receivedMessage = try await coordinator.nextClientMessage()
        #expect(receivedMessage == .clientHello(PrimaryRuntimeTestFixtures.clientHello))

        await transport.close()
        await coordinator.stop()
    }

    @Test("Live primary transport carries fragmented inbound server frames")
    func validateLoopbackReadPath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: await coordinator.port
        )
        let inboundStream = try await transport.connect()

        try await coordinator.sendFragmented(
            .serverHello(PrimaryRuntimeTestFixtures.serverHello),
            chunkLengths: [3, 5, 7]
        )

        let message = try await Self.nextServerMessage(from: inboundStream)
        #expect(message == .serverHello(PrimaryRuntimeTestFixtures.serverHello))

        await transport.close()
        await coordinator.stop()
    }

    @Test("Live primary transport retries through waiting until a loopback coordinator appears")
    func validateWaitingRecoveryPath() async throws {
        let reservedPort = try reserveLoopbackPort()
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: reservedPort
        )

        let connectTask = Task {
            try await transport.connect()
        }

        try await Task.sleep(for: .milliseconds(150))
        let coordinator = try await LoopbackPrimaryCoordinator.start(port: reservedPort)
        let inboundStream = try await withTimeout(.seconds(2)) {
            try await connectTask.value
        }

        let payload = try OpalFusion.Wire.PrimaryMessageEncoder().encode(
            .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )
        let framedBytes = try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: PrimaryRuntimeTestFixtures.baseline.framing
        )
        .encode(payload: payload)

        try await transport.write(framedBytes)
        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        try await coordinator.send(.serverHello(PrimaryRuntimeTestFixtures.serverHello))
        let message = try await Self.nextServerMessage(from: inboundStream)
        #expect(message == .serverHello(PrimaryRuntimeTestFixtures.serverHello))

        await transport.close()
        await coordinator.stop()
    }

    @Test("Live primary transport writes framed client messages to a TLS loopback coordinator")
    func validateTLSLoopbackWritePath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let transport = try await Self.makeTLSTransport(port: await coordinator.port)
        _ = try await transport.connect()

        let payload = try OpalFusion.Wire.PrimaryMessageEncoder().encode(
            .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )
        let framedBytes = try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: PrimaryRuntimeTestFixtures.baseline.framing
        )
        .encode(payload: payload)

        try await transport.write(framedBytes)

        let receivedMessage = try await coordinator.nextClientMessage()
        #expect(receivedMessage == .clientHello(PrimaryRuntimeTestFixtures.clientHello))

        await transport.close()
        await coordinator.stop()
    }

    @Test("Live primary transport carries fragmented inbound server frames over TLS")
    func validateTLSLoopbackReadPath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let transport = try await Self.makeTLSTransport(port: await coordinator.port)
        let inboundStream = try await transport.connect()

        try await coordinator.sendFragmented(
            .serverHello(PrimaryRuntimeTestFixtures.serverHello),
            chunkLengths: [3, 5, 7]
        )

        let message = try await Self.nextServerMessage(from: inboundStream)
        #expect(message == .serverHello(PrimaryRuntimeTestFixtures.serverHello))

        await transport.close()
        await coordinator.stop()
    }

    private static func nextServerMessage(
        from inboundStream: AsyncThrowingStream<[UInt8], Error>
    ) async throws -> OpalFusion.ProtocolModel.ServerMessage {
        var iterator = inboundStream.makeAsyncIterator()
        var frameDecoder = OpalFusion.Wire.PrimaryFrameDecoder(
            configuration: PrimaryRuntimeTestFixtures.baseline.framing
        )
        let messageDecoder = OpalFusion.Wire.PrimaryMessageDecoder()

        while let chunk = try await iterator.next() {
            let payloads = try frameDecoder.append(chunk)
            if let payload = payloads.first {
                return try messageDecoder.decodeServer(payload)
            }
        }

        throw LiveRuntimeTestSupportError.inboundStreamClosed
    }

    private static func makeTLSTransport(
        port: UInt16
    ) async throws -> OpalFusion.Runtime.LivePrimaryTransport {
        OpalFusion.Runtime.LivePrimaryTransport(
            host: LoopbackPrimaryTLSTestFixture.host,
            port: port,
            requiresTLS: true,
            tlsTrustAnchorCertificateDERs: try LoopbackPrimaryTLSTestFixture
                .trustAnchorCertificateDERs()
        )
    }
}
