// OpalFusion+Runtime+NetworkPrimaryConnection+ImplementationGroup1.swift

import CFNetwork
import Foundation
import Network
import OpalDiagnostics
import Security

extension OpalFusion.Runtime.NetworkPrimaryConnection {
    func connect(
        restartDelay: Duration
    ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent> {
        guard hasStarted == false else {
            throw OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted
        }

        hasStarted = true
        isReady = false
        isReceivePending = false
        isExplicitlyClosing = false
        didObservePeerEOF = false
        lastNonCancellationTransportError = nil

        let eventStream = makeEventStream()
        connection.stateUpdateHandler = { state in
            Task {
                await self.handleStateUpdate(
                    state,
                    restartDelay: restartDelay
                )
            }
        }

        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                self.readyContinuation = continuation
                connection.start(queue: queue)
            }
        } catch {
            finishEventStream()
            throw error
        }

        return eventStream
    }

    func send(content: Data?) async throws {
        guard isReady else {
            throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
        }

        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: content,
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

    func cancel() async {
        isExplicitlyClosing = true
        waitingRestartTask?.cancel()
        waitingRestartTask = nil
        readyContinuation?.resume(
            throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
        )
        readyContinuation = nil
        connection.cancel()
    }

    func makeEventStream() -> AsyncStream<
        OpalFusion.Runtime.PrimaryConnectionEvent
    > {
        var capturedContinuation: AsyncStream<
            OpalFusion.Runtime.PrimaryConnectionEvent
        >.Continuation?
        let eventStream = AsyncStream(bufferingPolicy: .unbounded) { continuation in
            capturedContinuation = continuation
        }
        self.eventContinuation = capturedContinuation
        return eventStream
    }

    func handleStateUpdate(
        _ state: NWConnection.State,
        restartDelay: Duration
    ) async {
        let event = Self.makeDiagnosticsEvent(for: state)
        OpalDiagnostics.logger(category: .fusionTransport).record(
            event: event,
            level: .opalFusionDefault(for: event),
            fields: [
                .operation("primary_network_state"),
                .phase(Self.describe(state))
            ] + Self.errorFields(for: state)
        )
        switch state {
        case .ready:
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            isReady = true
            lastNonCancellationTransportError = nil
            eventContinuation?.yield(.ready)
            readyContinuation?.resume()
            readyContinuation = nil
            if isReceivePending == false {
                scheduleReceive()
            }
        case let .failed(error):
            if readyContinuation != nil {
                recordNonCancellationTransportError(error)
            }
            handleTerminalFailure(error)
        case let .waiting(error):
            recordNonCancellationTransportError(error)
            handleWaitingState(
                error,
                restartDelay: restartDelay
            )
        case .cancelled:
            if isExplicitlyClosing {
                handleCancellation()
            } else if didObservePeerEOF {
                resetState(cancelUnderlying: false)
            } else {
                handleTerminalFailure(resolveCancellationError())
            }
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    func scheduleReceive() {
        isReceivePending = true
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
    ) async {
        isReceivePending = false

        if let data, data.isEmpty == false {
            eventContinuation?.yield(.received(data))
        }

        if let error {
            if isExplicitlyClosing && isCancellationError(error) {
                return
            }
            handleTerminalFailure(error)
            return
        }

        if isComplete {
            didObservePeerEOF = true
            eventContinuation?.yield(.peerEOF)
            finishEventStream()
            resetState(cancelUnderlying: true)
            return
        }

        scheduleReceive()
    }
}
