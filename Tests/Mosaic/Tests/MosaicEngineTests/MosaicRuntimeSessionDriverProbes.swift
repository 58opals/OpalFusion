// MosaicRuntimeSessionDriverProbes.swift

import Foundation
import Synchronization
@testable import MosaicEngine
@testable import OpalFusionCore
actor MosaicRuntimeSessionDriverInputProbe {
    typealias Driver = OpalFusion.Mosaic.RuntimeSessionDriver
    typealias Input = OpalFusion.Mosaic.RuntimeSession.Input

    enum ProbeFailure: Error {
        case injected
    }

    private let stream: Driver.Dependencies.InputStream
    private let continuation: Driver.Dependencies.InputStream.Continuation
    private var openedWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var closedWaiters: [UUID: CheckedContinuation<Void, Error>] = [:]
    private var hasOpened = false
    private var hasClosed = false
    private(set) var openCount = 0
    private(set) var closeCount = 0

    init() {
        let (stream, continuation) = Driver.Dependencies.InputStream.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func open() -> Driver.Dependencies.InputStream {
        openCount += 1
        hasOpened = true
        let waiters = openedWaiters.values
        openedWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        return stream
    }

    func close() {
        closeCount += 1
        hasClosed = true
        let waiters = closedWaiters.values
        closedWaiters.removeAll()
        for waiter in waiters { waiter.resume() }
        continuation.finish()
    }

    func waitUntilOpened() async throws {
        try Task.checkCancellation()
        guard !hasOpened else { return }
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    openedWaiters[identifier] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(identifier) }
        }
        try Task.checkCancellation()
    }

    func waitUntilClosed() async throws {
        try Task.checkCancellation()
        guard !hasClosed else { return }
        let identifier = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                } else {
                    closedWaiters[identifier] = continuation
                }
            }
        } onCancel: {
            Task { await self.cancelWaiter(identifier) }
        }
        try Task.checkCancellation()
    }

    private func cancelWaiter(_ identifier: UUID) {
        let waiter = openedWaiters.removeValue(forKey: identifier)
            ?? closedWaiters.removeValue(forKey: identifier)
        waiter?.resume(throwing: CancellationError())
    }

    func send(_ input: Input) {
        continuation.yield(input)
    }

    func finish() {
        continuation.finish()
    }

    func fail() {
        continuation.finish(throwing: ProbeFailure.injected)
    }
}

final class MosaicRuntimeSessionDriverOutputProbe: Sendable {
    typealias Output = OpalFusion.Mosaic.RuntimeSessionDriver.Output

    private struct Storage: Sendable {
        var outputs: [Output] = []
        var cancellationStates: [Bool] = []
    }

    private let storage = Mutex(Storage())

    func record(_ output: Output) {
        storage.withLock { storage in
            storage.outputs.append(output)
            storage.cancellationStates.append(Task.isCancelled)
        }
    }

    var outputs: [Output] {
        storage.withLock { $0.outputs }
    }

    var cancellationStates: [Bool] {
        storage.withLock { $0.cancellationStates }
    }
}
