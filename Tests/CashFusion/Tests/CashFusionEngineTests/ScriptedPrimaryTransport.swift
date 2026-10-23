// ScriptedPrimaryTransport.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
actor ScriptedPrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
    private let connectError: Error?
    private let writeError: Error?
    private let blocksConnect: Bool
    private let blocksClose: Bool
    private let inboundStream: AsyncThrowingStream<[UInt8], Error>
    private let inboundContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation
    private let closeEnteredStream: AsyncStream<Void>
    private let closeEnteredContinuation: AsyncStream<Void>.Continuation
    private var connectCallCount: Int = 0
    private var writtenPayloads: [[UInt8]] = []
    private var closeCallCount: Int = 0
    private var releasedConnectResult: Result<Void, Error>?
    private var connectContinuation: CheckedContinuation<Result<Void, Error>, Never>?
    private var closeReleaseWaiters: [CheckedContinuation<Void, Never>] = []
    private var isCloseReleased = false

    init(
        connectError: Error? = nil,
        writeError: Error? = nil,
        blocksConnect: Bool = false,
        blocksClose: Bool = false
    ) {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [UInt8].self,
            throwing: Error.self
        )
        self.connectError = connectError
        self.writeError = writeError
        self.blocksConnect = blocksConnect
        self.blocksClose = blocksClose
        self.inboundStream = stream
        self.inboundContinuation = continuation
        let (closeEnteredStream, closeEnteredContinuation) = AsyncStream<Void>.makeStream(
            bufferingPolicy: .bufferingNewest(1)
        )
        self.closeEnteredStream = closeEnteredStream
        self.closeEnteredContinuation = closeEnteredContinuation
        self.connectContinuation = nil
    }

    func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
        connectCallCount += 1

        if blocksConnect {
            let result: Result<Void, Error>
            if let releasedConnectResult {
                result = releasedConnectResult
            } else {
                result = await withCheckedContinuation { continuation in
                    connectContinuation = continuation
                }
            }

            switch result {
            case .success:
                break
            case let .failure(error):
                throw error
            }
        }

        if let connectError {
            throw connectError
        }
        return inboundStream
    }

    func write(_ bytes: [UInt8]) async throws {
        if let writeError {
            throw writeError
        }
        writtenPayloads.append(bytes)
    }

    func close() async {
        closeCallCount += 1
        closeEnteredContinuation.yield(())
        if blocksClose && !isCloseReleased {
            await withCheckedContinuation { continuation in
                closeReleaseWaiters.append(continuation)
            }
        }
        connectContinuation?.resume(
            returning: .failure(
                OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            )
        )
        connectContinuation = nil
        inboundContinuation.finish()
    }

    func waitForCloseEntered() async throws {
        for await _ in closeEnteredStream {
            try Task.checkCancellation()
            return
        }
        throw CancellationError()
    }

    func releaseClose() {
        isCloseReleased = true
        let waiters = closeReleaseWaiters
        closeReleaseWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }

    func yieldInboundBytes(_ bytes: [UInt8]) {
        inboundContinuation.yield(bytes)
    }

    func releaseConnect() {
        releasedConnectResult = .success(())
        connectContinuation?.resume(returning: .success(()))
        connectContinuation = nil
    }

    func failConnect(_ error: Error) {
        releasedConnectResult = .failure(error)
        connectContinuation?.resume(returning: .failure(error))
        connectContinuation = nil
    }

    func finishInbound(throwing error: Error? = nil) {
        inboundContinuation.finish(throwing: error)
    }

    var recordedConnectCallCount: Int {
        connectCallCount
    }

    var recordedWrittenPayloads: [[UInt8]] {
        writtenPayloads
    }

    var recordedCloseCallCount: Int {
        closeCallCount
    }

    var hasPendingConnect: Bool {
        connectContinuation != nil
    }
}
