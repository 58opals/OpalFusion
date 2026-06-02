// LivePrimaryTransportValidator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LivePrimaryTransportValidator {
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

        #expect(await factory.connection.cancellationCount == 1)
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

    static func nextServerMessage(
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

    static func makeTLSTransport(
        port: UInt16
    ) async throws -> OpalFusion.Runtime.LivePrimaryTransport {
        OpalFusion.Runtime.LivePrimaryTransport(
            host: LoopbackPrimaryTLSTestFixture.host,
            port: port,
            requiresTLS: true,
            tlsTrustAnchorCertificateDERs: try await LoopbackPrimaryTLSTestFixture
                .loadTrustAnchorCertificateDERs()
        )
    }

    static func makeFramedClientHello() throws -> [UInt8] {
        let payload = try OpalFusion.Wire.PrimaryMessageEncoder().encode(
            .clientHello(PrimaryRuntimeTestFixtures.clientHello)
        )
        return try OpalFusion.Wire.PrimaryFrameEncoder(
            configuration: PrimaryRuntimeTestFixtures.baseline.framing
        )
        .encode(payload: payload)
    }
}
