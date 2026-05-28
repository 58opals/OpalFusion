// LoopbackPrimaryCoordinator.swift

@testable import OpalFusion
import Foundation
import Network

actor LoopbackPrimaryCoordinator {
    private let listener: NWListener
    private let networkQueue: DispatchQueue
    private var connection: NWConnection?
    private var connectionReady: Bool
    private var portValue: UInt16
    private var frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
    private let frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder
    private let messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder
    private let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
    private var clientMessages: [OpalFusion.ProtocolModel.ClientMessage]
    private var clientMessageHistory: [OpalFusion.ProtocolModel.ClientMessage]
    private var serverMessageHistory: [OpalFusion.ProtocolModel.ServerMessage]
    private var messageWaiters: [CheckedContinuation<OpalFusion.ProtocolModel.ClientMessage, Error>]
    private var inboundError: Error?
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var isStopping: Bool

    static func start(
        port: UInt16? = nil,
        requiresTLS: Bool = false,
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) async throws -> LoopbackPrimaryCoordinator {
        let networkQueue = DispatchQueue(label: "OpalFusionTests.LoopbackPrimaryCoordinator")
        let parameters: NWParameters
        if requiresTLS {
            parameters = try await LoopbackPrimaryTLSTestFixture.makeListenerParameters()
        } else {
            parameters = NWParameters.tcp
        }
        let listener: NWListener
        if let port {
            listener = try NWListener(
                using: parameters,
                on: NWEndpoint.Port(rawValue: port)!
            )
        } else {
            listener = try NWListener(using: parameters, on: .any)
        }

        let coordinator = LoopbackPrimaryCoordinator(
            listener: listener,
            networkQueue: networkQueue,
            connectionReady: false,
            portValue: 0,
            frameDecoder: .init(configuration: baseline.framing),
            frameEncoder: .init(configuration: baseline.framing),
            messageEncoder: .init(),
            messageDecoder: .init(),
            clientMessages: [],
            clientMessageHistory: [],
            serverMessageHistory: [],
            messageWaiters: [],
            inboundError: nil,
            startContinuation: nil,
            isStopping: false
        )
        try await coordinator.startListener()
        return coordinator
    }

    static func start(
        reserving reservedPort: ReservedLoopbackPort,
        requiresTLS: Bool = false,
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) async throws -> LoopbackPrimaryCoordinator {
        let port = await reservedPort.port
        await reservedPort.release()
        return try await start(
            port: port,
            requiresTLS: requiresTLS,
            baseline: baseline
        )
    }

    private init(
        listener: NWListener,
        networkQueue: DispatchQueue,
        connectionReady: Bool,
        portValue: UInt16,
        frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder,
        frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder,
        messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder,
        messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder,
        clientMessages: [OpalFusion.ProtocolModel.ClientMessage],
        clientMessageHistory: [OpalFusion.ProtocolModel.ClientMessage],
        serverMessageHistory: [OpalFusion.ProtocolModel.ServerMessage],
        messageWaiters: [CheckedContinuation<OpalFusion.ProtocolModel.ClientMessage, Error>],
        inboundError: Error?,
        startContinuation: CheckedContinuation<Void, Error>?,
        isStopping: Bool
    ) {
        self.listener = listener
        self.networkQueue = networkQueue
        self.connection = nil
        self.connectionReady = connectionReady
        self.portValue = portValue
        self.frameDecoder = frameDecoder
        self.frameEncoder = frameEncoder
        self.messageEncoder = messageEncoder
        self.messageDecoder = messageDecoder
        self.clientMessages = clientMessages
        self.clientMessageHistory = clientMessageHistory
        self.serverMessageHistory = serverMessageHistory
        self.messageWaiters = messageWaiters
        self.inboundError = inboundError
        self.startContinuation = startContinuation
        self.isStopping = isStopping
    }

    var port: UInt16 {
        portValue
    }

    func stop() async {
        isStopping = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        connectionReady = false
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        finishWaiters(with: LiveRuntimeTestHarnessError.inboundStreamClosed)
    }

    func closeConnection() async {
        connection?.cancel()
    }

    func nextClientMessage(
        timeout: Duration = .seconds(1)
    ) async throws -> OpalFusion.ProtocolModel.ClientMessage {
        try await LiveRuntimeTestHarness.withTimeout(timeout) {
            try await self.awaitNextClientMessage()
        }
    }

    func send(_ message: OpalFusion.ProtocolModel.ServerMessage) async throws {
        serverMessageHistory.append(message)
        let payload = try messageEncoder.encode(message)
        let framedBytes = try frameEncoder.encode(payload: payload)
        try await send(bytes: framedBytes)
    }

    func sendFragmented(
        _ message: OpalFusion.ProtocolModel.ServerMessage,
        chunkLengths: [Int]
    ) async throws {
        let payload = try messageEncoder.encode(message)
        let framedBytes = try frameEncoder.encode(payload: payload)

        var cursor = 0
        for chunkLength in chunkLengths {
            guard cursor < framedBytes.count else {
                return
            }
            let upperBound = min(cursor + chunkLength, framedBytes.count)
            try await send(bytes: Array(framedBytes[cursor ..< upperBound]))
            cursor = upperBound
        }

        if cursor < framedBytes.count {
            try await send(bytes: Array(framedBytes[cursor...]))
        }
    }

    private func startListener() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            startContinuation = continuation
            listener.newConnectionHandler = { connection in
                Task {
                    await self.didAccept(connection)
                }
            }
            listener.stateUpdateHandler = { state in
                Task {
                    await self.handleListenerStateUpdate(state)
                }
            }
            listener.start(queue: networkQueue)
        }
    }

    private func didAccept(_ connection: NWConnection) {
        self.connection?.stateUpdateHandler = nil
        self.connection?.cancel()

        self.connection = connection
        self.connectionReady = false
        connection.stateUpdateHandler = { state in
            Task {
                await self.handleConnectionStateUpdate(state)
            }
        }
        connection.start(queue: networkQueue)
    }

    private func handleListenerStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            portValue = listener.port?.rawValue ?? 0
            startContinuation?.resume()
            startContinuation = nil
        case let .waiting(error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            failInbound(with: error)
        case let .failed(error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            failInbound(with: error)
        case .cancelled:
            startContinuation?.resume(
                throwing: LiveRuntimeTestHarnessError.inboundStreamClosed
            )
            startContinuation = nil
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func handleConnectionStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionReady = true
            scheduleReceive()
        case let .waiting(error):
            connectionReady = false
            connection = nil
            failInbound(with: error)
        case let .failed(error):
            connectionReady = false
            connection = nil
            failInbound(with: error)
        case .cancelled:
            connectionReady = false
            connection = nil
            if isStopping == false {
                finishInbound(with: LiveRuntimeTestHarnessError.inboundStreamClosed)
            }
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    private func scheduleReceive() {
        guard let connection else {
            return
        }

        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { data, _, isComplete, error in
            Task {
                await self.handleReceive(
                    data: data,
                    isComplete: isComplete,
                    error: error
                )
            }
        }
    }

    private func handleReceive(
        data: Data?,
        isComplete: Bool,
        error: NWError?
    ) {
        if let data, data.isEmpty == false {
            handleReceivedBytes([UInt8](data))
        }

        if let error {
            failInbound(with: error)
            return
        }

        if isComplete {
            finishInbound(with: LiveRuntimeTestHarnessError.inboundStreamClosed)
            return
        }

        scheduleReceive()
    }

    private func handleReceivedBytes(_ bytes: [UInt8]) {
        do {
            let payloads = try frameDecoder.append(bytes)
            for payload in payloads {
                let message = try messageDecoder.decodeClient(payload)
                clientMessageHistory.append(message)
                if messageWaiters.isEmpty == false {
                    let waiter = messageWaiters.removeFirst()
                    waiter.resume(returning: message)
                } else {
                    clientMessages.append(message)
                }
            }
        } catch {
            failInbound(with: error)
        }
    }

    private func send(bytes: [UInt8]) async throws {
        let connection = try await waitForConnection()
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(bytes),
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume()
                }
            )
        }
    }

    private func waitForConnection(
        timeout: Duration = .seconds(1)
    ) async throws -> NWConnection {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while connection == nil || connectionReady == false {
            if clock.now >= deadline {
                throw LiveRuntimeTestHarnessError.missingConnection
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        guard let connection, connectionReady else {
            throw LiveRuntimeTestHarnessError.missingConnection
        }

        return connection
    }

    private func awaitNextClientMessage() async throws -> OpalFusion.ProtocolModel.ClientMessage {
        if clientMessages.isEmpty == false {
            return clientMessages.removeFirst()
        }

        if let inboundError {
            throw inboundError
        }

        return try await withCheckedThrowingContinuation { continuation in
            messageWaiters.append(continuation)
        }
    }

    private func failInbound(with error: Error) {
        inboundError = error
        finishWaiters(with: error)
    }

    private func finishInbound(with error: Error) {
        inboundError = error
        finishWaiters(with: error)
    }

    private func finishWaiters(with error: Error) {
        let waiters = messageWaiters
        messageWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    func recordedClientMessages() -> [OpalFusion.ProtocolModel.ClientMessage] {
        clientMessageHistory
    }

    func recordedServerMessages() -> [OpalFusion.ProtocolModel.ServerMessage] {
        serverMessageHistory
    }
}
