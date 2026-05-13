// ReadyPrimaryConnection.swift

@testable import OpalFusion
import Foundation

actor ReadyPrimaryConnection: OpalFusion.Runtime.PrimaryConnectioning {
    private var eventContinuation: AsyncStream<
        OpalFusion.Runtime.PrimaryConnectionEvent
    >.Continuation?

    func connect(
        restartDelay _: Duration
    ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent> {
        AsyncStream(bufferingPolicy: .unbounded) { continuation in
            eventContinuation = continuation
            continuation.yield(.ready)
        }
    }

    func send(content _: Data?) async throws {}

    func cancel() async {
        eventContinuation?.yield(.cancelled)
        eventContinuation?.finish()
        eventContinuation = nil
    }
}
