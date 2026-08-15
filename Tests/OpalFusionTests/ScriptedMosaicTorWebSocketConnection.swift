// ScriptedMosaicTorWebSocketConnection.swift

@_spi(MosaicPrivateAlpha) @testable import OpalFusion

actor ScriptedMosaicTorWebSocketConnection:
    OpalFusion.Mosaic.TorWebSocketConnectioning
{
    enum ProbeFailure: Error {
        case injected
        case incomingMessageTooLarge
    }

    private let stream: MessageStream
    private let continuation: MessageStream.Continuation
    private var openWaiter: CheckedContinuation<Void, Never>?
    private var openSuspensionWaiter: CheckedContinuation<Void, Never>?
    private var closeWaiter: CheckedContinuation<Void, Never>?
    private var closeSuspensionWaiter: CheckedContinuation<Void, Never>?
    private var sendWaiter: CheckedContinuation<Void, Never>?
    private var sentTextCountWaiter: (
        count: Int,
        continuation: CheckedContinuation<Void, Never>
    )?
    private var openResume: CheckedContinuation<Void, any Error>?
    private var closeResume: CheckedContinuation<Void, Never>?
    private var sendResume: CheckedContinuation<Void, any Error>?
    private var hasOpened = false
    private var isClosed = false
    private var shouldSuspendNextOpen = false
    private var shouldSuspendNextClose = false
    private var shouldSuspendNextSend = false
    private var shouldFailNextOpen = false
    private var shouldFailNextSend = false
    private var hasSuspendedOpen = false
    private var hasSuspendedClose = false
    private var hasSuspendedSend = false

    private(set) var openCount = 0
    private(set) var closeCount = 0
    private(set) var sentTexts: [String] = []
    private(set) var openedMaximumIncomingMessageByteCount: Int?
    private(set) var deliveredMessageCount = 0
    private(set) var rejectedIncomingMessageCount = 0

    init() {
        let (stream, continuation) = MessageStream.makeStream()
        self.stream = stream
        self.continuation = continuation
    }

    func open(
        maximumIncomingMessageByteCount: Int
    ) async throws -> MessageStream {
        openCount += 1
        openedMaximumIncomingMessageByteCount = maximumIncomingMessageByteCount
        if shouldFailNextOpen {
            shouldFailNextOpen = false
            throw ProbeFailure.injected
        }
        if shouldSuspendNextOpen, !hasSuspendedOpen {
            hasSuspendedOpen = true
            openSuspensionWaiter?.resume()
            openSuspensionWaiter = nil
            try await withCheckedThrowingContinuation { continuation in
                openResume = continuation
            }
        }
        try Task.checkCancellation()
        guard !isClosed else { throw CancellationError() }
        hasOpened = true
        openWaiter?.resume()
        openWaiter = nil
        return stream
    }

    func send(text: String) async throws {
        guard !isClosed else { throw CancellationError() }
        sentTexts.append(text)
        if let waiter = sentTextCountWaiter,
           sentTexts.count >= waiter.count {
            sentTextCountWaiter = nil
            waiter.continuation.resume()
        }
        if shouldFailNextSend {
            shouldFailNextSend = false
            throw ProbeFailure.injected
        }
        guard shouldSuspendNextSend, !hasSuspendedSend else { return }
        hasSuspendedSend = true
        sendWaiter?.resume()
        sendWaiter = nil
        try await withCheckedThrowingContinuation { continuation in
            sendResume = continuation
        }
        guard !isClosed else { throw CancellationError() }
    }

    func close() async {
        guard !isClosed else { return }
        isClosed = true
        closeCount += 1
        openResume?.resume(throwing: CancellationError())
        openResume = nil
        sendResume?.resume(throwing: CancellationError())
        sendResume = nil
        continuation.finish()
        closeWaiter?.resume()
        closeWaiter = nil
        guard shouldSuspendNextClose, !hasSuspendedClose else { return }
        hasSuspendedClose = true
        closeSuspensionWaiter?.resume()
        closeSuspensionWaiter = nil
        await withCheckedContinuation { continuation in
            closeResume = continuation
        }
    }

    func suspendNextOpen() {
        shouldSuspendNextOpen = true
    }

    func suspendNextSend() {
        shouldSuspendNextSend = true
    }

    func suspendNextClose() {
        shouldSuspendNextClose = true
    }

    func failNextOpen() {
        shouldFailNextOpen = true
    }

    func failNextSend() {
        shouldFailNextSend = true
    }

    func waitUntilOpened() async {
        guard !hasOpened else { return }
        await withCheckedContinuation { continuation in
            openWaiter = continuation
        }
    }

    func waitUntilOpenSuspends() async {
        guard !hasSuspendedOpen else { return }
        await withCheckedContinuation { continuation in
            openSuspensionWaiter = continuation
        }
    }

    func resumeOpen() {
        openResume?.resume()
        openResume = nil
    }

    func waitUntilSendSuspends() async {
        guard !hasSuspendedSend else { return }
        await withCheckedContinuation { continuation in
            sendWaiter = continuation
        }
    }

    func waitUntilSentTextCount(_ count: Int) async {
        guard sentTexts.count < count else { return }
        await withCheckedContinuation { continuation in
            sentTextCountWaiter = (count, continuation)
        }
    }

    func resumeSend() {
        sendResume?.resume()
        sendResume = nil
    }

    func waitUntilCloseSuspends() async {
        guard !hasSuspendedClose else { return }
        await withCheckedContinuation { continuation in
            closeSuspensionWaiter = continuation
        }
    }

    func resumeClose() {
        closeResume?.resume()
        closeResume = nil
    }

    func waitUntilClosed() async {
        guard closeCount == 0 else { return }
        await withCheckedContinuation { continuation in
            closeWaiter = continuation
        }
    }

    func receive(_ message: OpalFusion.Mosaic.TorWebSocketMessage) {
        let byteCount: Int
        switch message {
        case let .text(data), let .binary(data):
            byteCount = data.count
        }
        guard let maximumIncomingMessageByteCount = openedMaximumIncomingMessageByteCount,
              byteCount <= maximumIncomingMessageByteCount else {
            rejectedIncomingMessageCount += 1
            continuation.finish(throwing: ProbeFailure.incomingMessageTooLarge)
            return
        }
        deliveredMessageCount += 1
        continuation.yield(message)
    }

    func finishInput() {
        continuation.finish()
    }

    func failInput() {
        continuation.finish(throwing: ProbeFailure.injected)
    }
}
