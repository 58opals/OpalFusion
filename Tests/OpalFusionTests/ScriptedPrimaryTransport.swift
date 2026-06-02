// ScriptedPrimaryTransport.swift

@testable import OpalFusion

actor ScriptedPrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
    private let connectError: Error?
    private let writeError: Error?
    private let blocksConnect: Bool
    private let inboundStream: AsyncThrowingStream<[UInt8], Error>
    private let inboundContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation
    private var connectCallCount: Int = 0
    private var writtenPayloads: [[UInt8]] = []
    private var closeCallCount: Int = 0
    private var connectContinuation: CheckedContinuation<Result<Void, Error>, Never>?

    init(
        connectError: Error? = nil,
        writeError: Error? = nil,
        blocksConnect: Bool = false
    ) {
        let (stream, continuation) = AsyncThrowingStream.makeStream(
            of: [UInt8].self,
            throwing: Error.self
        )
        self.connectError = connectError
        self.writeError = writeError
        self.blocksConnect = blocksConnect
        self.inboundStream = stream
        self.inboundContinuation = continuation
        self.connectContinuation = nil
    }

    func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
        connectCallCount += 1

        if blocksConnect {
            let result = await withCheckedContinuation { continuation in
                connectContinuation = continuation
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
        connectContinuation?.resume(
            returning: .failure(
                OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            )
        )
        connectContinuation = nil
        inboundContinuation.finish()
    }

    func yieldInboundBytes(_ bytes: [UInt8]) {
        inboundContinuation.yield(bytes)
    }

    func releaseConnect() {
        connectContinuation?.resume(returning: .success(()))
        connectContinuation = nil
    }

    func failConnect(_ error: Error) {
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
