// LoopbackPrimaryCoordinator+ValidationGroup1.swift

@testable import OpalFusion
import Foundation
import Network

extension LoopbackPrimaryCoordinator {
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

    func readNextClientMessage(
        timeout: Duration = .seconds(1)
    ) async throws -> OpalFusion.ProtocolModel.ClientMessage {
        try await LiveRuntimeTestHarness.withTimeout(timeout) {
            try await self.waitForNextClientMessage()
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

    func startListener() async throws {
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

    func didAccept(_ connection: NWConnection) {
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

    func handleListenerStateUpdate(_ state: NWListener.State) {
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
}
