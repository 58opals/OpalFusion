// LivePrimaryTransportValidator.swift

@testable import OpalFusion
import Foundation
import Network
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
        let reservedPort = try LiveRuntimeTestSupport.reserveLoopbackPort()
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: await reservedPort.port
        )

        let connectTask = Task {
            try await transport.connect()
        }

        try await Task.sleep(for: .milliseconds(150))
        let coordinator = try await LoopbackPrimaryCoordinator.start(reserving: reservedPort)
        let inboundStream = try await LiveRuntimeTestSupport.withTimeout(.seconds(2)) {
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

    @Test("Live primary transport preserves startup waiting errors across restart-triggered cancellation")
    func validateWaitingCancellationPreservesUnderlyingError() async throws {
        let underlyingError = NWError.posix(.ECONNRESET)
        let factory = ScriptedNetworkPrimaryConnectionFixture(
            startStates: [.waiting(underlyingError)],
            restartStates: [.cancelled]
        )
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: 8789,
            restartDelay: .zero,
            connectionFactory: { host, port, parameters in
                factory.make(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        )

        let connectTask = Task {
            try await transport.connect()
        }

        do {
            _ = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
                try await connectTask.value
            }
            Issue.record("Expected startup failure")
        } catch {
            #expect(String(describing: error) == String(describing: underlyingError))
        }

        #expect(await factory.connection.cancelCount() == 1)
    }

    @Test("Live primary transport cancels the underlying connection after terminal startup failure")
    func validateTerminalStartupFailureCancelsConnection() async throws {
        let underlyingError = NWError.posix(.ECONNRESET)
        let factory = ScriptedNetworkPrimaryConnectionFixture(
            startStates: [.failed(underlyingError)]
        )
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: 8789,
            connectionFactory: { host, port, parameters in
                factory.make(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        )

        do {
            _ = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
                try await transport.connect()
            }
            Issue.record("Expected startup failure")
        } catch {
            #expect(String(describing: error) == String(describing: underlyingError))
        }

        #expect(await factory.connection.cancelCount() == 1)
    }

    @Test("Live primary transport keeps explicit close cancellation after a stored waiting error")
    func validateExplicitCloseKeepsGenericCancellation() async throws {
        let factory = ScriptedNetworkPrimaryConnectionFixture(
            startStates: [.waiting(NWError.posix(.ECONNRESET))]
        )
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: 8789,
            restartDelay: .seconds(1),
            connectionFactory: { host, port, parameters in
                factory.make(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        )

        let connectTask = Task {
            try await transport.connect()
        }

        await factory.connection.waitUntilStarted()
        await transport.close()

        do {
            _ = try await LiveRuntimeTestSupport.withTimeout(.seconds(1)) {
                try await connectTask.value
            }
            Issue.record("Expected explicit close cancellation")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .primaryConnectionCancelled)
        } catch {
            Issue.record("Expected primaryConnectionCancelled, received \(String(describing: error))")
        }
    }

    @Test("Live primary transport allows immediate reconnect after closing a pending connect")
    func validateCloseClearsPendingConnectBeforeReconnect() async throws {
        let pendingConnection = BlockingStartPrimaryConnection()
        let readyConnection = ReadyPrimaryConnection()
        let factory = SequentialPrimaryConnectionFactory(
            connections: [
                pendingConnection,
                readyConnection
            ]
        )
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: 8789,
            connectionFactory: { host, port, parameters in
                factory.make(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        )
        let pendingConnectTask = Task {
            try await transport.connect()
        }

        await pendingConnection.waitUntilConnectStarted()
        await transport.close()

        _ = try await transport.connect()

        await pendingConnection.failConnect(
            OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
        )
        do {
            _ = try await pendingConnectTask.value
            Issue.record("Expected pending connect to fail after cancellation")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .primaryConnectionCancelled)
        }

        await transport.close()
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
            tlsTrustAnchorCertificateDERs: try await LoopbackPrimaryTLSTestFixture
                .trustAnchorCertificateDERs()
        )
    }
}

private final class SequentialPrimaryConnectionFactory: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [any OpalFusion.Runtime.PrimaryConnectioning]

    init(connections: [any OpalFusion.Runtime.PrimaryConnectioning]) {
        self.connections = connections
    }

    func make(
        host _: String,
        port _: UInt16,
        parameters _: NWParameters
    ) -> any OpalFusion.Runtime.PrimaryConnectioning {
        lock.lock()
        defer {
            lock.unlock()
        }
        return connections.removeFirst()
    }
}

private actor BlockingStartPrimaryConnection: OpalFusion.Runtime.PrimaryConnectioning {
    private var connectContinuation: CheckedContinuation<
        AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent>,
        Error
    >?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func connect(
        restartDelay _: Duration
    ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent> {
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            let waiters = startedWaiters
            startedWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func send(content _: Data?) async throws {
        throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
    }

    func cancel() async {}

    func waitUntilConnectStarted() async {
        guard connectContinuation == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            if connectContinuation == nil {
                startedWaiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    func failConnect(_ error: Error) {
        connectContinuation?.resume(throwing: error)
        connectContinuation = nil
    }
}

private actor ReadyPrimaryConnection: OpalFusion.Runtime.PrimaryConnectioning {
    private var eventContinuation: AsyncStream<
        OpalFusion.Runtime.PrimaryConnectionEvent
    >.Continuation?

    func connect(
        restartDelay _: Duration
    ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            eventContinuation = continuation
            continuation.yield(.ready)
        }
    }

    func send(content _: Data?) async throws {}

    func cancel() async {
        eventContinuation?.yield(.cancelled)
        eventContinuation?.finish()
        eventContinuation = nil
    }
}
