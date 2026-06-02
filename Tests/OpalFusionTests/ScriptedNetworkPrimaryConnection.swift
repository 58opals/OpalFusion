// ScriptedNetworkPrimaryConnection.swift

@testable import OpalFusion
import Foundation
import Network

actor ScriptedNetworkPrimaryConnection: OpalFusion.Runtime.PrimaryConnectioning {
    private let startStates: [NWConnection.State]
    private let restartStates: [NWConnection.State]
    private var eventContinuation: AsyncStream<
        OpalFusion.Runtime.PrimaryConnectionEvent
    >.Continuation?
    private var readyContinuation: CheckedContinuation<Void, Error>?
    private var startWaiters: [CheckedContinuation<Void, Never>]
    private var restartTask: Task<Void, Never>?
    private var lastNonCancellationTransportError: (any Error & Sendable)?
    private var hasStarted: Bool
    private var isExplicitlyClosing: Bool
    private var cancelCallCount: Int

    init(
        startStates: [NWConnection.State],
        restartStates: [NWConnection.State]
    ) {
        self.startStates = startStates
        self.restartStates = restartStates
        self.eventContinuation = nil
        self.readyContinuation = nil
        self.startWaiters = []
        self.restartTask = nil
        self.lastNonCancellationTransportError = nil
        self.hasStarted = false
        self.isExplicitlyClosing = false
        self.cancelCallCount = 0
    }

    func connect(
        restartDelay: Duration
    ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent> {
        guard hasStarted == false else {
            throw OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted
        }

        hasStarted = true
        isExplicitlyClosing = false
        lastNonCancellationTransportError = nil
        let waiters = startWaiters
        startWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }

        let eventStream = makeEventStream()
        do {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                self.readyContinuation = continuation
                self.process(
                    states: startStates,
                    restartDelay: restartDelay
                )
            }
        } catch {
            finishEvents()
            throw error
        }

        return eventStream
    }

    func send(content _: Data?) async throws {}

    func cancel() async {
        cancelCallCount += 1
        isExplicitlyClosing = true
        restartTask?.cancel()
        restartTask = nil
        readyContinuation?.resume(
            throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
        )
        readyContinuation = nil
        eventContinuation?.yield(.cancelled)
        finishEvents()
    }

    func cancelCount() -> Int {
        cancelCallCount
    }

    func waitUntilStarted() async {
        guard hasStarted == false else {
            return
        }

        await withCheckedContinuation { continuation in
            if hasStarted {
                continuation.resume()
            } else {
                startWaiters.append(continuation)
            }
        }
    }

    private func makeEventStream() -> AsyncStream<
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

    private func process(
        states: [NWConnection.State],
        restartDelay: Duration
    ) {
        for state in states {
            switch state {
            case .setup, .preparing:
                continue
            case .ready:
                eventContinuation?.yield(.ready)
                readyContinuation?.resume()
                readyContinuation = nil
                return
            case let .waiting(error):
                recordNonCancellationTransportError(error)
                eventContinuation?.yield(.waiting(error))
                restartTask?.cancel()
                guard restartDelay != .zero else {
                    process(
                        states: restartStates,
                        restartDelay: restartDelay
                    )
                    return
                }
                restartTask = Task {
                    try? await Task.sleep(for: restartDelay)
                    guard Task.isCancelled == false else {
                        return
                    }

                    self.process(
                        states: self.restartStates,
                        restartDelay: restartDelay
                    )
                }
                return
            case let .failed(error):
                handleTerminalFailure(error)
                return
            case .cancelled:
                if isExplicitlyClosing {
                    eventContinuation?.yield(.cancelled)
                    finishEvents()
                } else {
                    handleTerminalFailure(resolveCancellationError())
                }
                return
            @unknown default:
                continue
            }
        }
    }

    private func handleTerminalFailure(
        _ error: any Error & Sendable
    ) {
        cancelCallCount += 1
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        eventContinuation?.yield(.failed(error))
        finishEvents()
    }

    private func finishEvents() {
        guard let eventContinuation else {
            return
        }

        self.eventContinuation = nil
        eventContinuation.finish()
    }

    private func recordNonCancellationTransportError(
        _ error: any Error & Sendable
    ) {
        if isCancellationError(error) {
            return
        }

        lastNonCancellationTransportError = error
    }

    private func resolveCancellationError() -> any Error & Sendable {
        guard readyContinuation != nil,
              let lastNonCancellationTransportError else {
            return OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
        }

        return lastNonCancellationTransportError
    }

    private func isCancellationError(
        _ error: Error
    ) -> Bool {
        if let transportError = error as? OpalFusion.Runtime.LiveTransportError,
           transportError == .primaryConnectionCancelled {
            return true
        }

        if let networkError = error as? NWError,
           case let .posix(code) = networkError,
           code == .ECANCELED {
            return true
        }

        return false
    }
}
