// OpalFusion+Runtime+NetworkPrimaryConnection.swift

import CFNetwork
import Foundation
import Network
import OpalDiagnostics
import Security

extension OpalFusion.Runtime {
    actor NetworkPrimaryConnection: PrimaryConnectioning {
        private let connection: NWConnection
        private let queue = DispatchQueue(
            label: "OpalFusion.Runtime.NetworkPrimaryConnection"
        )
        private var eventContinuation: AsyncStream<
            OpalFusion.Runtime.PrimaryConnectionEvent
        >.Continuation?
        private var readyContinuation: CheckedContinuation<Void, Error>?
        private var waitingRestartTask: Task<Void, Never>?
        private var lastNonCancellationTransportError: (any Error & Sendable)?
        private var hasStarted: Bool
        private var isReady: Bool
        private var isReceivePending: Bool
        private var isExplicitlyClosing: Bool
        private var didObservePeerEOF: Bool

        init(
            host: String,
            port: UInt16,
            parameters: NWParameters
        ) throws {
            guard port > 0,
                  let endpointPort = NWEndpoint.Port(rawValue: port) else {
                throw OpalFusion.Runtime.LiveTransportError.invalidConfiguration(
                    "Primary connection port must be valid"
                )
            }
            self.connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
                using: parameters
            )
            self.eventContinuation = nil
            self.readyContinuation = nil
            self.waitingRestartTask = nil
            self.lastNonCancellationTransportError = nil
            self.hasStarted = false
            self.isReady = false
            self.isReceivePending = false
            self.isExplicitlyClosing = false
            self.didObservePeerEOF = false
        }

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
                finishEvents()
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

        private func handleStateUpdate(
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

        private func scheduleReceive() {
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

        private func handleReceive(
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
                finishEvents()
                resetState(cancelUnderlying: true)
                return
            }

            scheduleReceive()
        }

        private func handleWaitingState(
            _ error: NWError,
            restartDelay: Duration
        ) {
            guard isExplicitlyClosing == false else {
                return
            }

            isReady = false
            eventContinuation?.yield(.waiting(error))

            guard shouldRestartAfterWaiting(error) else {
                handleTerminalFailure(error)
                return
            }

            guard waitingRestartTask == nil else {
                return
            }

            waitingRestartTask = Task {
                try? await Task.sleep(for: restartDelay)
                guard Task.isCancelled == false else {
                    return
                }

                self.restartConnectionIfNeeded(
                    lastError: error
                )
            }
        }

        private func restartConnectionIfNeeded(
            lastError: NWError
        ) {
            defer {
                waitingRestartTask = nil
            }

            guard isExplicitlyClosing == false else {
                return
            }

            if readyContinuation == nil && eventContinuation == nil {
                handleTerminalFailure(lastError)
                return
            }

            connection.restart()
        }

        private func handleTerminalFailure(
            _ error: any Error & Sendable
        ) {
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
            eventContinuation?.yield(.failed(error))
            finishEvents()
            resetState(cancelUnderlying: true)
        }

        private func handleCancellation() {
            eventContinuation?.yield(.cancelled)
            finishEvents()
            resetState(cancelUnderlying: false)
        }

        private func recordNonCancellationTransportError(
            _ error: any Error & Sendable
        ) {
            guard isCancellationError(error) == false else {
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

            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain,
               nsError.code == Int(ECANCELED) {
                return true
            }

            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorCancelled {
                return true
            }

            return false
        }

        private func shouldRestartAfterWaiting(
            _ error: NWError
        ) -> Bool {
            switch error {
            case .tls:
                false
            case .dns, .posix, .wifiAware:
                true
            @unknown default:
                true
            }
        }

        private static func describe(
            _ state: NWConnection.State
        ) -> String {
            switch state {
            case .setup:
                "setup"
            case .preparing:
                "preparing"
            case .ready:
                "ready"
            case .waiting:
                "waiting"
            case .failed:
                "failed"
            case .cancelled:
                "cancelled"
            @unknown default:
                "unknown"
            }
        }

        static func makeDiagnosticsEvent(
            for state: NWConnection.State
        ) -> OpalDiagnostics.Event {
            switch state {
            case .ready:
                OpalDiagnostics.Event.primaryConnectionReady
            case .waiting:
                OpalDiagnostics.Event.primaryConnectionWaiting
            case .cancelled:
                OpalDiagnostics.Event.primaryConnectionCancelled
            case .failed:
                OpalDiagnostics.Event.transportError
            case .setup, .preparing:
                OpalDiagnostics.Event.primaryConnectionPreparing
            @unknown default:
                OpalDiagnostics.Event.transportError
            }
        }

        private static func errorFields(
            for state: NWConnection.State
        ) -> [OpalDiagnostics.Field] {
            switch state {
            case let .waiting(error), let .failed(error):
                OpalDiagnostics.Field.errorFields(for: error)
            default:
                []
            }
        }

        private func finishEvents() {
            guard let eventContinuation else {
                return
            }

            self.eventContinuation = nil
            eventContinuation.finish()
        }

        private func resetState(
            cancelUnderlying: Bool
        ) {
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            connection.stateUpdateHandler = nil
            if cancelUnderlying {
                connection.cancel()
            }
            readyContinuation = nil
            lastNonCancellationTransportError = nil
            isReady = false
            isReceivePending = false
            isExplicitlyClosing = false
            didObservePeerEOF = false
        }
    }
}
