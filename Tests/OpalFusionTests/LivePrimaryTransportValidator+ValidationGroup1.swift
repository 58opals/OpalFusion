// LivePrimaryTransportValidator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import Network
import Testing

extension LivePrimaryTransportValidator {
    @Test("Live primary transport writes framed client messages to a loopback coordinator")
    func validateLoopbackWritePath() async throws {
        let coordinator = try await LoopbackPrimaryCoordinator.start()

        let transport = OpalFusion.Runtime.LivePrimaryTransport(
            host: "127.0.0.1",
            port: await coordinator.port
        )
        _ = try await transport.connect()

        try await transport.write(Self.makeFramedClientHello())

        let receivedMessage = try await coordinator.readNextClientMessage()
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
            try await coordinator.readNextClientMessage()
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
            try await coordinator.readNextClientMessage(timeout: .milliseconds(1))
        } matching: { error in
            if case .timedOut = error {
                return true
            }
            return false
        }

        try await transport.write(Self.makeFramedClientHello())

        #expect(
            try await coordinator.readNextClientMessage()
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

        let receivedMessage = try await coordinator.readNextClientMessage()
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

        #expect(await factory.connection.cancellationCount == 1)
    }
}
