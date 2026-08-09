// MosaicRuntimeSessionDriverProbes.swift

import Synchronization
@testable import OpalFusion

actor MosaicRuntimeSessionDriverInputProbe {
    typealias Driver = OpalFusion.Mosaic.RuntimeSessionDriver
    typealias Input = OpalFusion.Mosaic.RuntimeSession.Input

    enum ProbeFailure: Error {
        case injected
    }

    private let stream: Driver.Dependencies.InputStream
    private let continuation: Driver.Dependencies.InputStream.Continuation
    private var openedContinuation: CheckedContinuation<Void, Never>?
    private var closedContinuations: [CheckedContinuation<Void, Never>] = []
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
        openedContinuation?.resume()
        openedContinuation = nil
        return stream
    }

    func close() {
        closeCount += 1
        hasClosed = true
        for continuation in closedContinuations {
            continuation.resume()
        }
        closedContinuations.removeAll(keepingCapacity: false)
        continuation.finish()
    }

    func waitUntilOpened() async {
        guard !hasOpened else {
            return
        }
        await withCheckedContinuation { continuation in
            openedContinuation = continuation
        }
    }

    func waitUntilClosed() async {
        guard !hasClosed else {
            return
        }
        await withCheckedContinuation { continuation in
            closedContinuations.append(continuation)
        }
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
