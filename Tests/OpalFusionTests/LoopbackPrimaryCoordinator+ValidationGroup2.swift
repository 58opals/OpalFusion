// LoopbackPrimaryCoordinator+ValidationGroup2.swift

@testable import OpalFusion
import Foundation
import Network

extension LoopbackPrimaryCoordinator {
    func handleConnectionStateUpdate(_ state: NWConnection.State) {
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

    func scheduleReceive() {
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

    func handleReceive(
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

    func handleReceivedBytes(_ bytes: [UInt8]) {
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

    func send(bytes: [UInt8]) async throws {
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

    func waitForConnection(
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

    func waitForNextClientMessage() async throws -> OpalFusion.ProtocolModel.ClientMessage {
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

    func cancelMessageWaiter(_ waiterID: UUID) {
        guard let waiterIndex = messageWaiters.firstIndex(where: { $0.id == waiterID }) else {
            return
        }

        let waiter = messageWaiters.remove(at: waiterIndex)
        waiter.continuation.resume(throwing: CancellationError())
    }

    func finishInbound(with error: Error) {
        inboundError = error
        finishWaiters(with: error)
    }

    func finishWaiters(with error: Error) {
        let waiters = messageWaiters
        messageWaiters.removeAll()
        for waiter in waiters {
            waiter.continuation.resume(throwing: error)
        }
    }
}
