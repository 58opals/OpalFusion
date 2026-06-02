// OpalFusion+Runtime+NetworkPrimaryConnection+ImplementationGroup2.swift

import CFNetwork
import Foundation
import Network
import OpalDiagnostics
import Security

extension OpalFusion.Runtime.NetworkPrimaryConnection {
    func handleWaitingState(
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

        guard restartDelay != .zero else {
            restartConnectionIfNeeded(lastError: error)
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

    func restartConnectionIfNeeded(
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

    func handleTerminalFailure(
        _ error: any Error & Sendable
    ) {
        waitingRestartTask?.cancel()
        waitingRestartTask = nil
        readyContinuation?.resume(throwing: error)
        readyContinuation = nil
        eventContinuation?.yield(.failed(error))
        finishEventStream()
        resetState(cancelUnderlying: true)
    }

    func handleCancellation() {
        eventContinuation?.yield(.cancelled)
        finishEventStream()
        resetState(cancelUnderlying: false)
    }

    func recordNonCancellationTransportError(
        _ error: any Error & Sendable
    ) {
        guard isCancellationError(error) == false else {
            return
        }

        lastNonCancellationTransportError = error
    }

    func resolveCancellationError() -> any Error & Sendable {
        guard readyContinuation != nil,
              let lastNonCancellationTransportError else {
            return OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
        }

        return lastNonCancellationTransportError
    }

    func isCancellationError(
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

    func shouldRestartAfterWaiting(
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

    static func describe(
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

    static func errorFields(
        for state: NWConnection.State
    ) -> [OpalDiagnostics.Field] {
        switch state {
        case let .waiting(error), let .failed(error):
            OpalDiagnostics.Field.errorFields(for: error)
        default:
            []
        }
    }
}
