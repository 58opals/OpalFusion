// ScriptedNetworkPrimaryConnection.swift

@testable import OpalFusion
import Foundation
import Network

final class ScriptedNetworkPrimaryConnection: OpalFusion.Runtime.PrimaryConnectioning, @unchecked Sendable {
    private let stateQueue = DispatchQueue(
        label: "OpalFusionTests.ScriptedNetworkPrimaryConnection"
    )
    private let startStates: [NWConnection.State]
    private let restartStates: [NWConnection.State]
    private var stateUpdateHandler: (@Sendable (NWConnection.State) -> Void)?
    private var hasStarted: Bool
    private var startContinuation: CheckedContinuation<Void, Never>?
    private var cancelCallCount: Int

    init(
        startStates: [NWConnection.State],
        restartStates: [NWConnection.State]
    ) {
        self.startStates = startStates
        self.restartStates = restartStates
        self.stateUpdateHandler = nil
        self.hasStarted = false
        self.startContinuation = nil
        self.cancelCallCount = 0
    }

    func setStateUpdateHandler(_ handler: (@Sendable (NWConnection.State) -> Void)?) {
        stateQueue.sync {
            self.stateUpdateHandler = handler
        }
    }

    func start(queue _: DispatchQueue) {
        let states = stateQueue.sync { () -> [NWConnection.State] in
            hasStarted = true
            startContinuation?.resume()
            startContinuation = nil
            return startStates
        }
        emit(states)
    }

    func send(content _: Data?, completion: NWConnection.SendCompletion) {
        switch completion {
        case let .contentProcessed(handler):
            handler(nil)
        case .idempotent:
            break
        @unknown default:
            break
        }
    }

    func receive(
        minimumIncompleteLength _: Int,
        maximumLength _: Int,
        completion _: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
    ) {}

    func restart() {
        emit(restartStates)
    }

    func cancel() {
        stateQueue.sync {
            cancelCallCount += 1
        }
    }

    func cancelCount() -> Int {
        stateQueue.sync {
            cancelCallCount
        }
    }

    func waitUntilStarted() async {
        let shouldWait = stateQueue.sync { hasStarted == false }
        guard shouldWait else {
            return
        }

        await withCheckedContinuation { continuation in
            stateQueue.sync {
                if hasStarted {
                    continuation.resume()
                } else {
                    startContinuation = continuation
                }
            }
        }
    }

    private func emit(
        _ states: [NWConnection.State]
    ) {
        let handler = stateQueue.sync { stateUpdateHandler }
        for state in states {
            handler?(state)
        }
    }
}
