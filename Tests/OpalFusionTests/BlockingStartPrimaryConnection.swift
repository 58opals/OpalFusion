// BlockingStartPrimaryConnection.swift

@testable import OpalFusion
import Foundation

actor BlockingStartPrimaryConnection: OpalFusion.Runtime.PrimaryConnectioning {
    private var connectContinuation: CheckedContinuation<
        AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent>,
        Error
    >?
    private var startedWaiters: [CheckedContinuation<Void, Never>] = []

    func connect(
        restartDelay _: Duration
    ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent> {
        try await withCheckedThrowingContinuation { continuation in
            connectContinuation = continuation
            let waiters = startedWaiters
            startedWaiters.removeAll()
            for waiter in waiters {
                waiter.resume()
            }
        }
    }

    func send(content _: Data?) async throws {
        throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
    }

    func cancel() async {}

    func waitUntilConnectStarted() async {
        guard connectContinuation == nil else {
            return
        }

        await withCheckedContinuation { continuation in
            if connectContinuation == nil {
                startedWaiters.append(continuation)
            } else {
                continuation.resume()
            }
        }
    }

    func failConnect(_ error: Error) {
        connectContinuation?.resume(throwing: error)
        connectContinuation = nil
    }
}
