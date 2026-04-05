// LiveRuntimeTestSupport.swift

@testable import OpalFusion
import Darwin
import Foundation
import OpalCrypto

enum LiveRuntimeTestSupportError: Swift.Error, Equatable {
    case timedOut(String)
    case missingConnection
    case inboundStreamClosed
    case signingInputNotFound
}

func withTimeout<T: Sendable>(
    _ duration: Duration,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }
        group.addTask {
            try await Task.sleep(for: duration)
            throw LiveRuntimeTestSupportError.timedOut(
                "Timed out after \(duration.wholeMilliseconds)ms"
            )
        }

        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}

actor LoopbackPrimaryCoordinator {
    private let serverFileDescriptor: Int32
    private let socketQueue: DispatchQueue
    private var clientFileDescriptor: Int32?
    private var portValue: UInt16
    private var frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
    private let frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder
    private let messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder
    private let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
    private var clientMessages: [OpalFusion.ProtocolModel.ClientMessage]
    private var clientMessageHistory: [OpalFusion.ProtocolModel.ClientMessage]
    private var serverMessageHistory: [OpalFusion.ProtocolModel.ServerMessage]
    private var messageWaiters: [CheckedContinuation<OpalFusion.ProtocolModel.ClientMessage, Error>]
    private var inboundError: Error?

    static func start(
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) async throws -> LoopbackPrimaryCoordinator {
        let serverFileDescriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard serverFileDescriptor >= 0 else {
            throw POSIXError(.ENOTCONN)
        }

        var reuseAddress: Int32 = 1
        guard setsockopt(
            serverFileDescriptor,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuseAddress,
            socklen_t(MemoryLayout<Int32>.size)
        ) == 0 else {
            Darwin.close(serverFileDescriptor)
            throw POSIXError(.ENOTCONN)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(0).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                Darwin.bind(
                    serverFileDescriptor,
                    reboundPointer,
                    socklen_t(MemoryLayout<sockaddr_in>.size)
                )
            }
        }
        guard bindResult == 0, listen(serverFileDescriptor, 1) == 0 else {
            Darwin.close(serverFileDescriptor)
            throw POSIXError(.ENOTCONN)
        }

        var boundAddress = sockaddr_in()
        var boundLength = socklen_t(MemoryLayout<sockaddr_in>.size)
        let nameResult = withUnsafeMutablePointer(to: &boundAddress) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { reboundPointer in
                getsockname(serverFileDescriptor, reboundPointer, &boundLength)
            }
        }
        guard nameResult == 0 else {
            Darwin.close(serverFileDescriptor)
            throw POSIXError(.ENOTCONN)
        }

        let coordinator = LoopbackPrimaryCoordinator(
            serverFileDescriptor: serverFileDescriptor,
            socketQueue: DispatchQueue(label: "OpalFusionTests.LoopbackPrimaryCoordinator"),
            portValue: UInt16(bigEndian: boundAddress.sin_port),
            frameDecoder: .init(configuration: baseline.framing),
            frameEncoder: .init(configuration: baseline.framing),
            messageEncoder: .init(),
            messageDecoder: .init(),
            clientMessages: [],
            clientMessageHistory: [],
            serverMessageHistory: [],
            messageWaiters: [],
            inboundError: nil
        )
        await coordinator.startAcceptLoop()
        return coordinator
    }

    private init(
        serverFileDescriptor: Int32,
        socketQueue: DispatchQueue,
        portValue: UInt16,
        frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder,
        frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder,
        messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder,
        messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder,
        clientMessages: [OpalFusion.ProtocolModel.ClientMessage],
        clientMessageHistory: [OpalFusion.ProtocolModel.ClientMessage],
        serverMessageHistory: [OpalFusion.ProtocolModel.ServerMessage],
        messageWaiters: [CheckedContinuation<OpalFusion.ProtocolModel.ClientMessage, Error>],
        inboundError: Error?
    ) {
        self.serverFileDescriptor = serverFileDescriptor
        self.socketQueue = socketQueue
        self.clientFileDescriptor = nil
        self.portValue = portValue
        self.frameDecoder = frameDecoder
        self.frameEncoder = frameEncoder
        self.messageEncoder = messageEncoder
        self.messageDecoder = messageDecoder
        self.clientMessages = clientMessages
        self.clientMessageHistory = clientMessageHistory
        self.serverMessageHistory = serverMessageHistory
        self.messageWaiters = messageWaiters
        self.inboundError = inboundError
    }

    var port: UInt16 {
        portValue
    }

    func stop() async {
        if let clientFileDescriptor {
            Darwin.shutdown(clientFileDescriptor, SHUT_RDWR)
            Darwin.close(clientFileDescriptor)
            self.clientFileDescriptor = nil
        }
        Darwin.close(serverFileDescriptor)
        finishWaiters(with: LiveRuntimeTestSupportError.inboundStreamClosed)
    }

    func closeConnection() async {
        if let clientFileDescriptor {
            Darwin.shutdown(clientFileDescriptor, SHUT_RDWR)
            Darwin.close(clientFileDescriptor)
            self.clientFileDescriptor = nil
        }
    }

    func nextClientMessage(
        timeout: Duration = .seconds(1)
    ) async throws -> OpalFusion.ProtocolModel.ClientMessage {
        try await withTimeout(timeout) {
            try await self.awaitNextClientMessage()
        }
    }

    func send(_ message: OpalFusion.ProtocolModel.ServerMessage) async throws {
        serverMessageHistory.append(message)
        let payload = try messageEncoder.encode(message)
        let framedBytes = try frameEncoder.encode(payload: payload)
        try await send(bytes: framedBytes)
    }

    func sendFragmented(
        _ message: OpalFusion.ProtocolModel.ServerMessage,
        chunkLengths: [Int]
    ) async throws {
        let payload = try messageEncoder.encode(message)
        let framedBytes = try frameEncoder.encode(payload: payload)

        var cursor = 0
        for chunkLength in chunkLengths {
            guard cursor < framedBytes.count else {
                return
            }
            let upperBound = min(cursor + chunkLength, framedBytes.count)
            try await send(bytes: Array(framedBytes[cursor ..< upperBound]))
            cursor = upperBound
        }

        if cursor < framedBytes.count {
            try await send(bytes: Array(framedBytes[cursor...]))
        }
    }

    private func startAcceptLoop() {
        socketQueue.async { [serverFileDescriptor] in
            let clientFileDescriptor = Darwin.accept(serverFileDescriptor, nil, nil)
            guard clientFileDescriptor >= 0 else {
                Task {
                    await self.failInbound(with: POSIXError(.ENOTCONN))
                }
                return
            }

            Task {
                await self.didAccept(clientFileDescriptor: clientFileDescriptor)
            }

            var buffer = [UInt8](repeating: 0, count: 65_536)
            while true {
                let bytesRead = Darwin.recv(
                    clientFileDescriptor,
                    &buffer,
                    buffer.count,
                    0
                )

                if bytesRead > 0 {
                    let bytes = Array(buffer[..<Int(bytesRead)])
                    Task {
                        await self.handleReceivedBytes(bytes)
                    }
                    continue
                }

                if bytesRead == 0 {
                    Task {
                        await self.finishInbound(with: LiveRuntimeTestSupportError.inboundStreamClosed)
                    }
                } else {
                    Task {
                        await self.failInbound(with: POSIXError(.ENOTCONN))
                    }
                }
                break
            }
        }
    }

    private func didAccept(clientFileDescriptor: Int32) {
        self.clientFileDescriptor = clientFileDescriptor
    }

    private func handleReceivedBytes(_ bytes: [UInt8]) {
        do {
            let payloads = try frameDecoder.append(bytes)
            for payload in payloads {
                let message = try messageDecoder.decodeClient(payload)
                clientMessageHistory.append(message)
                if messageWaiters.isEmpty == false {
                    let waiter = messageWaiters.removeFirst()
                    waiter.resume(returning: message)
                } else {
                    clientMessages.append(message)
                }
            }
        } catch {
            failInbound(with: error)
        }
    }

    private func send(bytes: [UInt8]) async throws {
        let clientFileDescriptor = try await waitForConnection()
        let result = bytes.withUnsafeBytes { buffer in
            Darwin.send(
                clientFileDescriptor,
                buffer.baseAddress,
                buffer.count,
                0
            )
        }

        guard result == bytes.count else {
            throw POSIXError(.ENOTCONN)
        }
    }

    private func waitForConnection(
        timeout: Duration = .seconds(1)
    ) async throws -> Int32 {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while clientFileDescriptor == nil {
            if clock.now >= deadline {
                throw LiveRuntimeTestSupportError.missingConnection
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        guard let clientFileDescriptor else {
            throw LiveRuntimeTestSupportError.missingConnection
        }

        return clientFileDescriptor
    }

    private func awaitNextClientMessage() async throws -> OpalFusion.ProtocolModel.ClientMessage {
        if clientMessages.isEmpty == false {
            return clientMessages.removeFirst()
        }

        if let inboundError {
            throw inboundError
        }

        return try await withCheckedThrowingContinuation { continuation in
            messageWaiters.append(continuation)
        }
    }

    private func failInbound(with error: Error) {
        inboundError = error
        finishWaiters(with: error)
    }

    private func finishInbound(with error: Error) {
        inboundError = error
        finishWaiters(with: error)
    }

    private func finishWaiters(with error: Error) {
        let waiters = messageWaiters
        messageWaiters.removeAll()
        for waiter in waiters {
            waiter.resume(throwing: error)
        }
    }

    func recordedClientMessages() -> [OpalFusion.ProtocolModel.ClientMessage] {
        clientMessageHistory
    }

    func recordedServerMessages() -> [OpalFusion.ProtocolModel.ServerMessage] {
        serverMessageHistory
    }
}

struct RecordedHostEvent: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier?
    let event: OpalFusion.Host.Event
}

struct RecordedRoundEvent: Sendable, Equatable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let event: OpalFusion.Host.Event
}

struct TimedRecordedRoundEvent: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let event: OpalFusion.Host.Event
    let recordedAt: Date
}

struct TimedRecordedHostEvent: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier?
    let event: OpalFusion.Host.Event
    let recordedAt: Date
}

struct TimedRoundRequestRecord: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let recordedAt: Date
}

struct TimedTransactionProposalRecord: Sendable {
    let roundIdentifier: OpalFusion.Round.Identifier
    let proposal: OpalFusion.Host.TransactionFinalizationProposal
    let recordedAt: Date
}

struct TimedClientSessionSnapshot: Sendable {
    let snapshot: OpalFusion.Client.Session.Snapshot
    let recordedAt: Date
}

actor RecordedHostEventSink {
    private var events: [RecordedHostEvent] = []
    private var timedEvents: [TimedRecordedHostEvent] = []

    func record(
        roundIdentifier: OpalFusion.Round.Identifier?,
        event: OpalFusion.Host.Event
    ) {
        timedEvents.append(
            .init(
                roundIdentifier: roundIdentifier,
                event: event,
                recordedAt: Date()
            )
        )
        events.append(
            .init(
                roundIdentifier: roundIdentifier,
                event: event
            )
        )
    }

    func snapshot() -> [RecordedHostEvent] {
        events
    }

    func timedSnapshot() -> [TimedRecordedHostEvent] {
        timedEvents
    }
}

actor RecordedRoundEventObserver: OpalFusion.Host.EventObserver {
    private var events: [RecordedRoundEvent] = []
    private var timedEvents: [TimedRecordedRoundEvent] = []

    func receive(
        _ event: OpalFusion.Host.Event,
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async {
        timedEvents.append(
            .init(
                roundIdentifier: roundIdentifier,
                event: event,
                recordedAt: Date()
            )
        )
        events.append(
            .init(
                roundIdentifier: roundIdentifier,
                event: event
            )
        )
    }

    func snapshot() -> [RecordedRoundEvent] {
        events
    }

    func timedSnapshot() -> [TimedRecordedRoundEvent] {
        timedEvents
    }
}

actor RecordedClientStateObserver: OpalFusion.Client.StateObserver {
    private var snapshots: [OpalFusion.Client.Session.Snapshot] = []
    private var timedSnapshots: [TimedClientSessionSnapshot] = []

    func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
        timedSnapshots.append(
            .init(
                snapshot: snapshot,
                recordedAt: Date()
            )
        )
        snapshots.append(snapshot)
    }

    func snapshot() -> [OpalFusion.Client.Session.Snapshot] {
        snapshots
    }

    func timedSnapshot() -> [TimedClientSessionSnapshot] {
        timedSnapshots
    }
}

final class ScriptedNowProvider: @unchecked Sendable {
    private let lock = NSLock()
    private var currentInstant: OpalFusion.Execution.Instant

    init(unixSeconds: UInt64) {
        self.currentInstant = .init(unixSeconds: unixSeconds)
    }

    func now() -> OpalFusion.Execution.Instant {
        lock.lock()
        defer { lock.unlock() }
        return currentInstant
    }

    func set(unixSeconds: UInt64) {
        lock.lock()
        currentInstant = .init(unixSeconds: unixSeconds)
        lock.unlock()
    }
}

actor DelayedParticipantInputProvider: OpalFusion.Host.ParticipantInputProvider {
    private let participantInputs: [OpalFusion.Host.ParticipantInput]
    private let participantOutputs: [OpalFusion.Host.ParticipantOutput]
    private let delay: Duration
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var requestRecords: [TimedRoundRequestRecord] = []

    init(
        participantInputs: [OpalFusion.Host.ParticipantInput],
        participantOutputs: [OpalFusion.Host.ParticipantOutput] = [],
        delay: Duration = .zero
    ) {
        self.participantInputs = participantInputs
        self.participantOutputs = participantOutputs
        self.delay = delay
        self.requestedRoundIdentifiers = []
    }

    func reservedInputs(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> [OpalFusion.Host.ParticipantInput] {
        requestedRoundIdentifiers.append(roundIdentifier)
        requestRecords.append(
            .init(
                roundIdentifier: roundIdentifier,
                recordedAt: Date()
            )
        )

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        return participantInputs
    }

    func participantReservation(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        requestedRoundIdentifiers.append(roundIdentifier)
        requestRecords.append(
            .init(
                roundIdentifier: roundIdentifier,
                recordedAt: Date()
            )
        )

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        return .init(
            inputs: participantInputs,
            outputs: participantOutputs
        )
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func timedRequestRecords() -> [TimedRoundRequestRecord] {
        requestRecords
    }
}

actor DelayedTransactionAssembler: OpalFusion.Host.TransactionAssembler {
    private let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    private let delay: Duration
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var proposals: [OpalFusion.Host.TransactionFinalizationProposal] = []
    private var proposalRecords: [TimedTransactionProposalRecord] = []

    init(
        finalizedTransaction: OpalFusion.Host.FinalizedTransaction,
        delay: Duration = .zero
    ) {
        self.finalizedTransaction = finalizedTransaction
        self.delay = delay
        self.requestedRoundIdentifiers = []
        self.proposals = []
    }

    func finalizeTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        requestedRoundIdentifiers.append(roundIdentifier)
        proposals.append(proposal)
        proposalRecords.append(
            .init(
                roundIdentifier: roundIdentifier,
                proposal: proposal,
                recordedAt: Date()
            )
        )

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        return finalizedTransaction
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func recordedProposals() -> [OpalFusion.Host.TransactionFinalizationProposal] {
        proposals
    }

    func timedProposalRecords() -> [TimedTransactionProposalRecord] {
        proposalRecords
    }
}

actor SigningTransactionAssembler: OpalFusion.Host.TransactionAssembler {
    private let participantInput: OpalFusion.Host.ParticipantInput
    private let participantInputPrivateKey: [UInt8]
    private let unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])?
    private let delay: Duration
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var proposals: [OpalFusion.Host.TransactionFinalizationProposal] = []
    private var proposalRecords: [TimedTransactionProposalRecord] = []
    private var signatures: [[UInt8]] = []

    init(
        participantInput: OpalFusion.Host.ParticipantInput,
        participantInputPrivateKey: [UInt8],
        unlockingScriptBuilder: (([UInt8], [UInt8]) -> [UInt8])? = nil,
        delay: Duration = .zero
    ) {
        self.participantInput = participantInput
        self.participantInputPrivateKey = participantInputPrivateKey
        self.unlockingScriptBuilder = unlockingScriptBuilder
        self.delay = delay
        self.requestedRoundIdentifiers = []
        self.proposals = []
        self.signatures = []
    }

    func finalizeTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        requestedRoundIdentifiers.append(roundIdentifier)
        proposals.append(proposal)
        proposalRecords.append(
            .init(
                roundIdentifier: roundIdentifier,
                proposal: proposal,
                recordedAt: Date()
            )
        )

        if delay > .zero {
            try await Task.sleep(for: delay)
        }

        let signingResult = try finalizedTransaction(for: proposal)
        signatures.append(signingResult.signature)
        return signingResult.transaction
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func recordedProposals() -> [OpalFusion.Host.TransactionFinalizationProposal] {
        proposals
    }

    func timedProposalRecords() -> [TimedTransactionProposalRecord] {
        proposalRecords
    }

    func recordedSignatures() -> [[UInt8]] {
        signatures
    }

    private func finalizedTransaction(
        for proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) throws -> (transaction: OpalFusion.Host.FinalizedTransaction, signature: [UInt8]) {
        guard let participantInputPublicKey = participantInput.publicKey else {
            throw LiveRuntimeTestSupportError.inboundStreamClosed
        }

        var transaction = try OpalFusion.Execution.BCHTransaction.parse(
            proposal.serializedUnsignedTransaction
        )
        let previousTransactionHashLittleEndian = Array(
            participantInput.outpointTransactionHash.reversed()
        )
        guard let inputIndex = transaction.inputs.firstIndex(where: { input in
            input.previousTransactionHashLittleEndian == previousTransactionHashLittleEndian &&
                input.previousOutputIndex == participantInput.outpointIndex
        }) else {
            throw LiveRuntimeTestSupportError.signingInputNotFound
        }
        let sighash = try transaction.signatureHash(
            forInputAt: inputIndex,
            lockingScript: participantInput.lockingScript,
            amountSatoshis: participantInput.amountSatoshis
        )
        let signature = try Array(
            OpalCrypto.Signature.sign(
                message: Data(sighash),
                privateKey: Data(participantInputPrivateKey),
                format: .schnorr,
                nonce: .bip340Deterministic
            )
        )

        let unlockingScript = unlockingScriptBuilder?(
            signature,
            participantInputPublicKey
        ) ?? ([0x41] + signature + [0x41] + [0x21] + participantInputPublicKey)

        transaction = transaction.settingUnlockingScript(unlockingScript, at: inputIndex)
        return (
            .init(serializedTransaction: try transaction.serialized()),
            signature
        )
    }
}

actor ScriptedCovertTransport: OpalFusion.Runtime.CovertTransporting {
    private var preparedPlans: [OpalFusion.Runtime.CovertPreparationPlan] = []
    private var performedRequests: [OpalFusion.Runtime.CovertRequest] = []
    private var queuedResponses: [[UInt8]] = []
    private var resetCount: Int = 0

    func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws {
        preparedPlans.append(plan)
    }

    func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
        performedRequests.append(request)
        if queuedResponses.isEmpty {
            return []
        }
        return queuedResponses.removeFirst()
    }

    func reset() async {
        resetCount += 1
        queuedResponses = []
    }

    func enqueueResponse(_ response: [UInt8]) {
        queuedResponses.append(response)
    }

    func recordedPreparationPlans() -> [OpalFusion.Runtime.CovertPreparationPlan] {
        preparedPlans
    }

    func recordedRequests() -> [OpalFusion.Runtime.CovertRequest] {
        performedRequests
    }

    func recordedResetCount() -> Int {
        resetCount
    }
}

actor ScriptedPrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
    private let connectError: Error?
    private let writeError: Error?
    private let inboundStream: AsyncThrowingStream<[UInt8], Error>
    private let inboundContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation
    private var connectCallCount: Int = 0
    private var writtenPayloads: [[UInt8]] = []
    private var closeCallCount: Int = 0

    init(
        connectError: Error? = nil,
        writeError: Error? = nil
    ) {
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self, throwing: Error.self)
        self.connectError = connectError
        self.writeError = writeError
        self.inboundStream = stream
        self.inboundContinuation = continuation
    }

    func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
        connectCallCount += 1
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
        inboundContinuation.finish()
    }

    func yieldInboundBytes(_ bytes: [UInt8]) {
        inboundContinuation.yield(bytes)
    }

    func finishInbound(throwing error: Error? = nil) {
        inboundContinuation.finish(throwing: error)
    }

    func recordedConnectCallCount() -> Int {
        connectCallCount
    }

    func recordedWrittenPayloads() -> [[UInt8]] {
        writtenPayloads
    }

    func recordedCloseCallCount() -> Int {
        closeCallCount
    }
}

actor RecordedCovertRequestExecutor {
    private let responseData: Data
    private let statusCode: Int
    private var requests: [URLRequest] = []

    init(
        responseData: Data,
        statusCode: Int = 200
    ) {
        self.responseData = responseData
        self.statusCode = statusCode
        self.requests = []
    }

    func execute(
        session _: URLSession,
        request: URLRequest
    ) async throws -> (Data, URLResponse) {
        requests.append(request)
        guard let url = request.url else {
            throw LiveRuntimeTestSupportError.inboundStreamClosed
        }
        let response = HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }
}
