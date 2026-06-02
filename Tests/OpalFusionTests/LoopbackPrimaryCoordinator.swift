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
    private var messageWaiters: [
        (
            id: UUID,
            continuation: CheckedContinuation<OpalFusion.ProtocolModel.ClientMessage, Error>
        )
    ]
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
            guard port > 0,
                  let endpointPort = NWEndpoint.Port(rawValue: port) else {
                throw LiveRuntimeTestHarnessError.invalidLoopbackPort(port)
            }
            listener = try NWListener(
                using: parameters,
                on: endpointPort
            )
        } else {
            listener = try NWListener(using: parameters, on: .any)
        }

        let coordinator = LoopbackPrimaryCoordinator(
            listener: listener,
            networkQueue: networkQueue,
            baseline: baseline
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
        baseline: OpalFusion.Transport.BaselineConfiguration
    ) {
        self.listener = listener
        self.networkQueue = networkQueue
        self.connection = nil
        self.connectionReady = false
        self.portValue = 0
        self.frameDecoder = .init(configuration: baseline.framing)
        self.frameEncoder = .init(configuration: baseline.framing)
        self.messageEncoder = .init()
        self.messageDecoder = .init()
        self.clientMessages = []
        self.clientMessageHistory = []
        self.serverMessageHistory = []
        self.messageWaiters = []
        self.inboundError = nil
        self.startContinuation = nil
        self.isStopping = false
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
            guard chunkLength > 0 else {
                throw LiveRuntimeTestHarnessError.invalidFragmentLength(chunkLength)
            }
            guard cursor < framedBytes.count else {
                return
            }
            let byteCount = min(chunkLength, framedBytes.count - cursor)
            let upperBound = cursor + byteCount
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
            finishInbound(with: error)
        case let .failed(error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            finishInbound(with: error)
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
            finishInbound(with: error)
        case let .failed(error):
            connectionReady = false
            connection = nil
            finishInbound(with: error)
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
            finishInbound(with: error)
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
                    waiter.continuation.resume(returning: message)
                } else {
                    clientMessages.append(message)
                }
            }
        } catch {
            finishInbound(with: error)
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

        while true {
            if let connection, connectionReady {
                return connection
            }

            if clock.now >= deadline {
                throw LiveRuntimeTestHarnessError.missingConnection
            }
            try await Task.sleep(for: .milliseconds(10))
        }
    }

    private func awaitNextClientMessage() async throws -> OpalFusion.ProtocolModel.ClientMessage {
        if clientMessages.isEmpty == false {
            return clientMessages.removeFirst()
        }

        if let inboundError {
            throw inboundError
        }

        let waiterID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                messageWaiters.append(
                    (
                        id: waiterID,
                        continuation: continuation
                    )
                )
            }
        } onCancel: {
            Task {
                await self.cancelMessageWaiter(waiterID)
            }
        }
    }

    private func cancelMessageWaiter(_ waiterID: UUID) {
        guard let waiterIndex = messageWaiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }

        let waiter = messageWaiters.remove(at: waiterIndex)
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func finishInbound(with error: Error) {
        inboundError = error
        finishWaiters(with: error)
    }

    private func finishWaiters(with error: Error) {
        let waiters = messageWaiters
        messageWaiters.removeAll()
        for waiter in waiters {
            waiter.continuation.resume(throwing: error)
        }
    }

    func recordedClientMessages() -> [OpalFusion.ProtocolModel.ClientMessage] {
        clientMessageHistory
    }

    func recordedServerMessages() -> [OpalFusion.ProtocolModel.ServerMessage] {
        serverMessageHistory
    }
}
