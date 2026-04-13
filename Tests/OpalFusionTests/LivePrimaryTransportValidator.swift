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

    @Test("Live primary transport preserves startup waiting errors across restart-triggered cancellation")
    func validateWaitingCancellationPreservesUnderlyingError() async throws {
        let underlyingError = NWError.posix(.ECONNRESET)
        let factory = ScriptedNetworkPrimaryConnectionFactory(
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
            _ = try await withTimeout(.seconds(1)) {
                try await connectTask.value
            }
            Issue.record("Expected startup failure")
        } catch {
            #expect(String(describing: error) == String(describing: underlyingError))
        }
    }

    @Test("Live primary transport keeps explicit close cancellation after a stored waiting error")
    func validateExplicitCloseKeepsGenericCancellation() async throws {
        let factory = ScriptedNetworkPrimaryConnectionFactory(
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
            _ = try await withTimeout(.seconds(1)) {
                try await connectTask.value
            }
            Issue.record("Expected explicit close cancellation")
        } catch let error as OpalFusion.Runtime.LiveTransportError {
            #expect(error == .primaryConnectionCancelled)
        } catch {
            Issue.record("Expected primaryConnectionCancelled, received \(String(describing: error))")
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

final class ScriptedNetworkPrimaryConnectionFactory: @unchecked Sendable {
    let connection: ScriptedNetworkPrimaryConnection

    init(
        startStates: [NWConnection.State],
        restartStates: [NWConnection.State] = []
    ) {
        self.connection = ScriptedNetworkPrimaryConnection(
            startStates: startStates,
            restartStates: restartStates
        )
    }

    func make(
        host _: String,
        port _: UInt16,
        parameters _: NWParameters
    ) -> any OpalFusion.Runtime.PrimaryConnectioning {
        connection
    }
}

final class ScriptedNetworkPrimaryConnection: OpalFusion.Runtime.PrimaryConnectioning, @unchecked Sendable {
    private let stateQueue = DispatchQueue(
        label: "OpalFusionTests.ScriptedNetworkPrimaryConnection"
    )
    private let startStates: [NWConnection.State]
    private let restartStates: [NWConnection.State]
    private var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)?
    private var hasStarted: Bool
    private var startContinuation: CheckedContinuation<Void, Never>?

    init(
        startStates: [NWConnection.State],
        restartStates: [NWConnection.State]
    ) {
        self.startStates = startStates
        self.restartStates = restartStates
        self.stateUpdateHandler = nil
        self.hasStarted = false
        self.startContinuation = nil
    }

    func setStateUpdateHandler(_ handler: (@Sendable (NWConnection.State) -> Void)?) {
        stateQueue.sync {
            self.stateUpdateHandler = handler
        }
    }

    func start(queue _: DispatchQueue) {
        let states = stateQueue.sync { () -> [NWConnection.State] in
            hasStarted = true
            startContinuation?.resume()
            startContinuation = nil
            return startStates
        }
        emit(states)
    }

    func send(content _: Data?, completion: NWConnection.SendCompletion) {
        switch completion {
        case let .contentProcessed(handler):
            handler(nil)
        case .idempotent:
            break
        @unknown default:
            break
        }
    }

    func receive(
        minimumIncompleteLength _: Int,
        maximumLength _: Int,
        completion _: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    ) {}

    func restart() {
        emit(restartStates)
    }

    func cancel() {}

    func waitUntilStarted() async {
        let shouldWait = stateQueue.sync { hasStarted == false }
        guard shouldWait else {
            return
        }

        await withCheckedContinuation { continuation in
            stateQueue.sync {
                if hasStarted {
                    continuation.resume()
                } else {
                    startContinuation = continuation
                }
            }
        }
    }

    private func emit(
        _ states: [NWConnection.State]
    ) {
        let handler = stateQueue.sync { stateUpdateHandler }
        for state in states {
            handler?(state)
        }
    }
}
