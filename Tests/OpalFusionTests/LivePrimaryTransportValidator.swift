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

        try await transport.write(Self.makeFramedClientHello())

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

    @Test("Loopback primary coordinator rejects invalid fragment lengths without trapping")
    func validateInvalidFragmentLengthRejection() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        await Self.expectHarnessError("invalidFragmentLength(0)") {
            try await coordinator.sendFragmented(
                .serverHello(PrimaryRuntimeTestFixtures.serverHello),
                chunkLengths: [0]
            )
        } matching: { error in
            error == .invalidFragmentLength(0)
        }

        await coordinator.stop()
    }

    @Test("Live primary transport retries through waiting until a loopback coordinator appears")
    func validateWaitingRecoveryPath() async throws {
        let reservedPort = try LiveRuntimeTestHarness.reserveLoopbackPort()
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: await reservedPort.port
        )

        let connectTask = Task {
            try await transport.connect()
        }
        defer {
            connectTask.cancel()
        }

        try await Task.sleep(for: .milliseconds(150))
        let coordinator = try await LoopbackPrimaryCoordinator.start(reserving: reservedPort)
        let inboundStream = try await LiveRuntimeTestHarness.withTimeout(.seconds(2)) {
            try await connectTask.value
        }

        try await transport.write(Self.makeFramedClientHello())
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

    @Test("Loopback primary coordinator removes cancelled client message waiters")
    func validateCancelledClientMessageWaiterDoesNotConsumeNextMessage() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: await coordinator.port
        )
        _ = try await transport.connect()

        await Self.expectHarnessError("client message wait timeout") {
            try await coordinator.nextClientMessage(timeout: .milliseconds(1))
        } matching: { error in
            if case .timedOut = error {
                return true
            }
            return false
        }

        try await transport.write(Self.makeFramedClientHello())

        #expect(
            try await coordinator.nextClientMessage()
                == .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )

        await transport.close()
        await coordinator.stop()
    }

    @Test("Live primary transport writes framed client messages to a TLS loopback coordinator")
    func validateTLSLoopbackWritePath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start(requiresTLS: true)
        let transport = try await Self.makeTLSTransport(port: await coordinator.port)
        _ = try await transport.connect()

        try await transport.write(Self.makeFramedClientHello())

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
        let transport = Self.makeScriptedTransport(
            factory,
            restartDelay: .zero
        )

        let connectTask = Task {
            try await transport.connect()
        }
        defer {
            connectTask.cancel()
        }

        do {
            _ = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                try await connectTask.value
            }
            Issue.record("Expected startup failure")
        } catch {
            Self.expectPOSIXError(.ECONNRESET, from: error)
        }

        #expect(await factory.connection.cancelCount() == 1)
    }

    @Test("Live primary transport cancels the underlying connection after terminal startup failure")
    func validateTerminalStartupFailureCancelsConnection() async throws {
        let underlyingError = NWError.posix(.ECONNRESET)
        let factory = ScriptedNetworkPrimaryConnectionFixture(
            startStates: [.failed(underlyingError)]
        )
        let transport = Self.makeScriptedTransport(factory)

        do {
            _ = try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                try await transport.connect()
            }
            Issue.record("Expected startup failure")
        } catch {
            Self.expectPOSIXError(.ECONNRESET, from: error)
        }

        #expect(await factory.connection.cancelCount() == 1)
    }

    @Test("Live primary transport keeps explicit close cancellation after a stored waiting error")
    func validateExplicitCloseKeepsGenericCancellation() async throws {
        let factory = ScriptedNetworkPrimaryConnectionFixture(
            startStates: [.waiting(NWError.posix(.ECONNRESET))]
        )
        let transport = Self.makeScriptedTransport(
            factory,
            restartDelay: .seconds(1)
        )

        let connectTask = Task {
            try await transport.connect()
        }
        defer {
            connectTask.cancel()
        }

        await factory.connection.waitUntilStarted()
        await transport.close()

        await Self.expectLiveTransportError(.primaryConnectionCancelled) {
            try await LiveRuntimeTestHarness.withTimeout(.seconds(1)) {
                try await connectTask.value
            }
        }
    }

    @Test("Live primary transport allows immediate reconnect after closing a pending connect")
    func validateCloseClearsPendingConnectBeforeReconnect() async throws {
        let pendingConnection = BlockingStartPrimaryConnection()
        let readyConnection = ReadyPrimaryConnection()
        let factory = SequentialPrimaryConnectionBuilder(
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
        defer {
            pendingConnectTask.cancel()
        }

        await pendingConnection.waitUntilConnectStarted()
        await transport.close()

        _ = try await transport.connect()

        await pendingConnection.failConnect(
            OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
        )
        await Self.expectLiveTransportError(.primaryConnectionCancelled) {
            try await pendingConnectTask.value
        }

        await transport.close()
    }

    @Test("Live primary transport rejects invalid connection ports without trapping")
    func validateInvalidConnectionPortRejection() async {
        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: 0
        )

        await Self.expectLiveTransportError(
            .invalidConfiguration("Primary connection port must be valid")
        ) {
            try await transport.connect()
        }
    }

    @Test("Loopback primary coordinator rejects invalid explicit ports without trapping")
    func validateInvalidLoopbackCoordinatorPortRejection() async {
        await Self.expectHarnessError("invalidLoopbackPort(0)") {
            try await LoopbackPrimaryCoordinator.start(port: 0)
        } matching: { error in
            error == .invalidLoopbackPort(0)
        }
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

        throw LiveRuntimeTestHarnessError.inboundStreamClosed
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

    private static func makeFramedClientHello() throws -> [UInt8] {
        let payload = try OpalFusion.Wire.PrimaryMessageEncoder().encode(
            .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )
        return try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: PrimaryRuntimeTestFixtures.baseline.framing
        )
        .encode(payload: payload)
    }
}

private extension LivePrimaryTransportValidator {
    static func makeScriptedTransport(
        _ factory: ScriptedNetworkPrimaryConnectionFixture,
        restartDelay: Duration = .milliseconds(100)
    ) -> OpalFusion.Runtime.LivePrimaryTransport {
        OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: 8789,
            restartDelay: restartDelay,
            connectionFactory: { host, port, parameters in
                factory.make(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        )
    }

    static func expectLiveTransportError<Success>(
        _ expectedError: OpalFusion.Runtime.LiveTransportError,
        from operation: () async throws -> Success
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected \(expectedError)")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == expectedError)
        } catch {
            Issue.record("Expected \(expectedError), received \(String(describing: error))")
        }
    }

    static func expectHarnessError<Success>(
        _ expectedDescription: String,
        from operation: () async throws -> Success,
        matching matches: (LiveRuntimeTestHarnessError) -> Bool
    ) async {
        do {
            _ = try await operation()
            Issue.record("Expected \(expectedDescription)")
        } catch let error as LiveRuntimeTestHarnessError {
            #expect(matches(error), "Expected \(expectedDescription), received \(error)")
        } catch {
            Issue.record("Expected \(expectedDescription), received \(String(describing: error))")
        }
    }

    static func expectPOSIXError(
        _ expectedCode: POSIXErrorCode,
        from error: any Error
    ) {
        guard let networkError = error as? NWError else {
            Issue.record("Expected NWError, received \(String(describing: error))")
            return
        }

        guard case let .posix(actualCode) = networkError else {
            Issue.record("Expected POSIX NWError, received \(String(describing: networkError))")
            return
        }

        #expect(actualCode == expectedCode)
    }
}
