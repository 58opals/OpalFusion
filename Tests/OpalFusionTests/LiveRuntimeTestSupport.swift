// LiveRuntimeTestSupport.swift

@testable import OpalFusion
import Foundation
import Network
import OpalCrypto
import Security
import Darwin

enum LiveRuntimeTestSupportError: Swift.Error, Equatable {
    case timedOut(String)
    case missingConnection
    case inboundStreamClosed
    case signingInputNotFound
    case invalidTLSFixture(String)
}

enum LoopbackPrimaryTLSTestFixture {
    static let host = "localhost"
    private static let pkcs12Passphrase = "OpalFusionTests"
    private static let materialResult: Result<Material, LiveRuntimeTestSupportError> = {
        do {
            return .success(try makeMaterial())
        } catch let error as LiveRuntimeTestSupportError {
            return .failure(error)
        } catch {
            return .failure(
                .invalidTLSFixture("TLS loopback material generation failed: \(error)")
            )
        }
    }()

    private struct Material: @unchecked Sendable {
        let certificateDER: Data
        let localIdentity: sec_identity_t
    }

    static func trustAnchorCertificateDERs() throws -> [Data] {
        [try material().certificateDER]
    }

    static func makeListenerParameters() throws -> NWParameters {
        let tlsOptions = NWProtocolTLS.Options()
        sec_protocol_options_set_local_identity(
            tlsOptions.securityProtocolOptions,
            try material().localIdentity
        )

        let parameters = NWParameters(
            tls: tlsOptions,
            tcp: NWProtocolTCP.Options()
        )
        return parameters
    }

    private static func material() throws -> Material {
        switch materialResult {
        case let .success(material):
            return material
        case let .failure(error):
            throw error
        }
    }

    private static func makeMaterial() throws -> Material {
        let cleanupDirectory = try prepareServerFiles()
        let keyURL = cleanupDirectory.appendingPathComponent("localhost.key.pem")
        let certificateURL = cleanupDirectory.appendingPathComponent("localhost.cert.pem")
        let pkcs12URL = cleanupDirectory.appendingPathComponent("localhost.identity.p12")

        defer {
            try? FileManager.default.removeItem(at: cleanupDirectory)
        }

        try runOpenSSL(
            [
                "req",
                "-x509",
                "-newkey",
                "rsa:2048",
                "-nodes",
                "-sha256",
                "-days",
                "3650",
                "-subj",
                "/CN=\(host)",
                "-addext",
                "subjectAltName=DNS:\(host)",
                "-keyout",
                keyURL.path,
                "-out",
                certificateURL.path
            ]
        )
        try runOpenSSL(
            [
                "pkcs12",
                "-export",
                "-passout",
                "pass:\(pkcs12Passphrase)",
                "-out",
                pkcs12URL.path,
                "-inkey",
                keyURL.path,
                "-in",
                certificateURL.path
            ]
        )

        let pkcs12Data = try Data(contentsOf: pkcs12URL)
        let certificatePEM = try String(contentsOf: certificateURL, encoding: .utf8)
        let certificateDER = try decodePEM(certificatePEM)
        let importOptions = [
            kSecImportExportPassphrase as String: pkcs12Passphrase
        ] as CFDictionary
        var importedItems: CFArray?
        let importStatus = SecPKCS12Import(
            pkcs12Data as CFData,
            importOptions,
            &importedItems
        )
        guard importStatus == errSecSuccess,
              let importedItems = importedItems as? [[String: Any]],
              let importedItem = importedItems.first
        else {
            throw LiveRuntimeTestSupportError.invalidTLSFixture(
                "TLS loopback identity import failed with status \(importStatus)"
            )
        }

        let identity = importedItem[kSecImportItemIdentity as String] as! SecIdentity
        guard let certificate = SecCertificateCreateWithData(
            nil,
            certificateDER as CFData
        ) else {
            throw LiveRuntimeTestSupportError.invalidTLSFixture(
                "TLS loopback certificate could not be materialized"
            )
        }

        guard let localIdentity = sec_identity_create_with_certificates(
            identity,
            [certificate] as CFArray
        ) else {
            throw LiveRuntimeTestSupportError.invalidTLSFixture(
                "TLS loopback local identity could not be created"
            )
        }

        return Material(
            certificateDER: certificateDER,
            localIdentity: localIdentity
        )
    }

    private static func prepareServerFiles() throws -> URL {
        let cleanupDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: cleanupDirectory,
            withIntermediateDirectories: true
        )
        return cleanupDirectory
    }

    private static func runOpenSSL(_ arguments: [String]) throws {
        let process = Process()
        let errorPipe = Pipe()

        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.standardError = errorPipe

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorSummary = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw LiveRuntimeTestSupportError.invalidTLSFixture(
                "TLS loopback OpenSSL command failed: \(errorSummary ?? arguments.joined(separator: " "))"
            )
        }
    }

    private static func decodePEM(_ pem: String) throws -> Data {
        let base64 = pem
            .split(separator: "\n")
            .filter { $0.hasPrefix("-----") == false }
            .joined()

        guard let data = Data(base64Encoded: base64) else {
            throw LiveRuntimeTestSupportError.invalidTLSFixture(
                "TLS loopback certificate fixture could not be decoded"
            )
        }

        return data
    }
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

final class ReservedLoopbackPort: @unchecked Sendable {
    let port: UInt16
    private var socketDescriptor: Int32?

    init(
        port: UInt16,
        socketDescriptor: Int32
    ) {
        self.port = port
        self.socketDescriptor = socketDescriptor
    }

    deinit {
        release()
    }

    func release() {
        guard let socketDescriptor else {
            return
        }

        _ = close(socketDescriptor)
        self.socketDescriptor = nil
    }
}

func reserveLoopbackPort() throws -> ReservedLoopbackPort {
    let socketDescriptor = socket(AF_INET, SOCK_STREAM, 0)
    guard socketDescriptor >= 0 else {
        throw POSIXError(.EADDRNOTAVAIL)
    }

    var address = sockaddr_in()
    address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = 0
    address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

    let bindResult = withUnsafePointer(to: &address) { addressPointer in
        addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            bind(
                socketDescriptor,
                socketAddress,
                socklen_t(MemoryLayout<sockaddr_in>.size)
            )
        }
    }
    guard bindResult == 0 else {
        _ = close(socketDescriptor)
        throw POSIXError(.EADDRNOTAVAIL)
    }

    var boundAddress = sockaddr_in()
    var boundAddressLength = socklen_t(MemoryLayout<sockaddr_in>.size)
    let nameResult = withUnsafeMutablePointer(to: &boundAddress) { addressPointer in
        addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
            getsockname(socketDescriptor, socketAddress, &boundAddressLength)
        }
    }
    guard nameResult == 0 else {
        _ = close(socketDescriptor)
        throw POSIXError(.EADDRNOTAVAIL)
    }

    return ReservedLoopbackPort(
        port: UInt16(bigEndian: boundAddress.sin_port),
        socketDescriptor: socketDescriptor
    )
}

actor LoopbackPrimaryCoordinator {
    private let listener: NWListener
    private let networkQueue: DispatchQueue
    private var connection: NWConnection?
    private var connectionReady: Bool
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
    private var startContinuation: CheckedContinuation<Void, Error>?
    private var isStopping: Bool

    static func start(
        port: UInt16? = nil,
        requiresTLS: Bool = false,
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) async throws -> LoopbackPrimaryCoordinator {
        let networkQueue = DispatchQueue(label: "OpalFusionTests.LoopbackPrimaryCoordinator")
        let parameters: NWParameters
        if requiresTLS {
            parameters = try LoopbackPrimaryTLSTestFixture.makeListenerParameters()
        } else {
            parameters = NWParameters.tcp
        }
        let listener: NWListener
        if let port {
            listener = try NWListener(
                using: parameters,
                on: NWEndpoint.Port(rawValue: port)!
            )
        } else {
            listener = try NWListener(using: parameters, on: .any)
        }

        let coordinator = LoopbackPrimaryCoordinator(
            listener: listener,
            networkQueue: networkQueue,
            connectionReady: false,
            portValue: 0,
            frameDecoder: .init(configuration: baseline.framing),
            frameEncoder: .init(configuration: baseline.framing),
            messageEncoder: .init(),
            messageDecoder: .init(),
            clientMessages: [],
            clientMessageHistory: [],
            serverMessageHistory: [],
            messageWaiters: [],
            inboundError: nil,
            startContinuation: nil,
            isStopping: false
        )
        try await coordinator.startListener()
        return coordinator
    }

    static func start(
        reserving reservedPort: ReservedLoopbackPort,
        requiresTLS: Bool = false,
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) async throws -> LoopbackPrimaryCoordinator {
        let port = reservedPort.port
        reservedPort.release()
        return try await start(
            port: port,
            requiresTLS: requiresTLS,
            baseline: baseline
        )
    }

    private init(
        listener: NWListener,
        networkQueue: DispatchQueue,
        connectionReady: Bool,
        portValue: UInt16,
        frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder,
        frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder,
        messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder,
        messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder,
        clientMessages: [OpalFusion.ProtocolModel.ClientMessage],
        clientMessageHistory: [OpalFusion.ProtocolModel.ClientMessage],
        serverMessageHistory: [OpalFusion.ProtocolModel.ServerMessage],
        messageWaiters: [CheckedContinuation<OpalFusion.ProtocolModel.ClientMessage, Error>],
        inboundError: Error?,
        startContinuation: CheckedContinuation<Void, Error>?,
        isStopping: Bool
    ) {
        self.listener = listener
        self.networkQueue = networkQueue
        self.connection = nil
        self.connectionReady = connectionReady
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
        self.startContinuation = startContinuation
        self.isStopping = isStopping
    }

    var port: UInt16 {
        portValue
    }

    func stop() async {
        isStopping = true
        connection?.stateUpdateHandler = nil
        connection?.cancel()
        connection = nil
        connectionReady = false
        listener.stateUpdateHandler = nil
        listener.newConnectionHandler = nil
        listener.cancel()
        finishWaiters(with: LiveRuntimeTestSupportError.inboundStreamClosed)
    }

    func closeConnection() async {
        connection?.cancel()
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

    private func startListener() async throws {
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            startContinuation = continuation
            listener.newConnectionHandler = { connection in
                Task {
                    await self.didAccept(connection)
                }
            }
            listener.stateUpdateHandler = { state in
                Task {
                    await self.handleListenerStateUpdate(state)
                }
            }
            listener.start(queue: networkQueue)
        }
    }

    private func didAccept(_ connection: NWConnection) {
        self.connection?.stateUpdateHandler = nil
        self.connection?.cancel()

        self.connection = connection
        self.connectionReady = false
        connection.stateUpdateHandler = { state in
            Task {
                await self.handleConnectionStateUpdate(state)
            }
        }
        connection.start(queue: networkQueue)
    }

    private func handleListenerStateUpdate(_ state: NWListener.State) {
        switch state {
        case .ready:
            portValue = listener.port?.rawValue ?? 0
            startContinuation?.resume()
            startContinuation = nil
        case let .waiting(error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            failInbound(with: error)
        case let .failed(error):
            startContinuation?.resume(throwing: error)
            startContinuation = nil
            failInbound(with: error)
        case .cancelled:
            startContinuation?.resume(
                throwing: LiveRuntimeTestSupportError.inboundStreamClosed
            )
            startContinuation = nil
        case .setup:
            break
        @unknown default:
            break
        }
    }

    private func handleConnectionStateUpdate(_ state: NWConnection.State) {
        switch state {
        case .ready:
            connectionReady = true
            scheduleReceive()
        case let .waiting(error):
            connectionReady = false
            connection = nil
            failInbound(with: error)
        case let .failed(error):
            connectionReady = false
            connection = nil
            failInbound(with: error)
        case .cancelled:
            connectionReady = false
            connection = nil
            if isStopping == false {
                finishInbound(with: LiveRuntimeTestSupportError.inboundStreamClosed)
            }
        case .setup, .preparing:
            break
        @unknown default:
            break
        }
    }

    private func scheduleReceive() {
        guard let connection else {
            return
        }

        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 65_536
        ) { data, _, isComplete, error in
            Task {
                await self.handleReceive(
                    data: data,
                    isComplete: isComplete,
                    error: error
                )
            }
        }
    }

    private func handleReceive(
        data: Data?,
        isComplete: Bool,
        error: NWError?
    ) {
        if let data, data.isEmpty == false {
            handleReceivedBytes([UInt8](data))
        }

        if let error {
            failInbound(with: error)
            return
        }

        if isComplete {
            finishInbound(with: LiveRuntimeTestSupportError.inboundStreamClosed)
            return
        }

        scheduleReceive()
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
        let connection = try await waitForConnection()
        try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<Void, Error>) in
            connection.send(
                content: Data(bytes),
                completion: .contentProcessed { error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }

                    continuation.resume()
                }
            )
        }
    }

    private func waitForConnection(
        timeout: Duration = .seconds(1)
    ) async throws -> NWConnection {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: timeout)

        while connection == nil || connectionReady == false {
            if clock.now >= deadline {
                throw LiveRuntimeTestSupportError.missingConnection
            }
            try await Task.sleep(for: .milliseconds(10))
        }

        guard let connection, connectionReady else {
            throw LiveRuntimeTestSupportError.missingConnection
        }

        return connection
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

actor BlockingParticipantInputProvider: OpalFusion.Host.ParticipantInputProvider {
    private let reservation: OpalFusion.Host.ParticipantReservation
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var reservationContinuation: CheckedContinuation<Result<OpalFusion.Host.ParticipantReservation, Error>, Never>?

    init(
        reservation: OpalFusion.Host.ParticipantReservation
    ) {
        self.reservation = reservation
    }

    func reservedInputs(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> [OpalFusion.Host.ParticipantInput] {
        let reservation = try await participantReservation(for: roundIdentifier)
        return reservation.inputs
    }

    func participantReservation(
        for roundIdentifier: OpalFusion.Round.Identifier
    ) async throws -> OpalFusion.Host.ParticipantReservation {
        requestedRoundIdentifiers.append(roundIdentifier)
        let result = await withCheckedContinuation { continuation in
            reservationContinuation = continuation
        }

        switch result {
        case let .success(reservation):
            return reservation
        case let .failure(error):
            throw error
        }
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func releaseReservation(
        _ reservation: OpalFusion.Host.ParticipantReservation? = nil
    ) {
        reservationContinuation?.resume(returning: .success(reservation ?? self.reservation))
        reservationContinuation = nil
    }

    func failReservation(
        _ error: Error
    ) {
        reservationContinuation?.resume(returning: .failure(error))
        reservationContinuation = nil
    }
}

actor BlockingTransactionAssembler: OpalFusion.Host.TransactionAssembler {
    private let finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    private var requestedRoundIdentifiers: [OpalFusion.Round.Identifier] = []
    private var proposals: [OpalFusion.Host.TransactionFinalizationProposal] = []
    private var transactionContinuation: CheckedContinuation<Result<OpalFusion.Host.FinalizedTransaction, Error>, Never>?

    init(
        finalizedTransaction: OpalFusion.Host.FinalizedTransaction
    ) {
        self.finalizedTransaction = finalizedTransaction
    }

    func finalizeTransaction(
        for roundIdentifier: OpalFusion.Round.Identifier,
        proposal: OpalFusion.Host.TransactionFinalizationProposal
    ) async throws -> OpalFusion.Host.FinalizedTransaction {
        requestedRoundIdentifiers.append(roundIdentifier)
        proposals.append(proposal)
        let result = await withCheckedContinuation { continuation in
            transactionContinuation = continuation
        }

        switch result {
        case let .success(transaction):
            return transaction
        case let .failure(error):
            throw error
        }
    }

    func requestedRounds() -> [OpalFusion.Round.Identifier] {
        requestedRoundIdentifiers
    }

    func recordedProposals() -> [OpalFusion.Host.TransactionFinalizationProposal] {
        proposals
    }

    func releaseTransaction(
        _ finalizedTransaction: OpalFusion.Host.FinalizedTransaction? = nil
    ) {
        transactionContinuation?.resume(
            returning: .success(finalizedTransaction ?? self.finalizedTransaction)
        )
        transactionContinuation = nil
    }

    func failTransaction(
        _ error: Error
    ) {
        transactionContinuation?.resume(returning: .failure(error))
        transactionContinuation = nil
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

actor BlockingCovertTransport: OpalFusion.Runtime.CovertTransporting {
    private var preparedPlans: [OpalFusion.Runtime.CovertPreparationPlan] = []
    private var performedRequests: [OpalFusion.Runtime.CovertRequest] = []
    private var resetCount: Int = 0
    private let blocksPrepare: Bool
    private let blocksPerform: Bool
    private var prepareContinuation: CheckedContinuation<Void, Never>?
    private var performContinuation: CheckedContinuation<Result<[UInt8], Error>, Never>?

    init(
        blocksPrepare: Bool = false,
        blocksPerform: Bool = false
    ) {
        self.blocksPrepare = blocksPrepare
        self.blocksPerform = blocksPerform
        self.prepareContinuation = nil
        self.performContinuation = nil
    }

    func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws {
        preparedPlans.append(plan)

        if blocksPrepare {
            await withCheckedContinuation { continuation in
                prepareContinuation = continuation
            }
        }
    }

    func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
        performedRequests.append(request)

        if blocksPerform {
            let result = await withCheckedContinuation { continuation in
                performContinuation = continuation
            }
            switch result {
            case let .success(responseBytes):
                return responseBytes
            case let .failure(error):
                throw error
            }
        }

        return []
    }

    func reset() async {
        resetCount += 1
    }

    func releasePrepare() {
        prepareContinuation?.resume()
        prepareContinuation = nil
    }

    func releasePerform(response responseBytes: [UInt8]) {
        performContinuation?.resume(returning: .success(responseBytes))
        performContinuation = nil
    }

    func failPerform(_ error: Error) {
        performContinuation?.resume(returning: .failure(error))
        performContinuation = nil
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
        let (stream, continuation) = AsyncThrowingStream.makeStream(of: [UInt8].self, throwing: Error.self)
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

    func recordedConnectCallCount() -> Int {
        connectCallCount
    }

    func recordedWrittenPayloads() -> [[UInt8]] {
        writtenPayloads
    }

    func recordedCloseCallCount() -> Int {
        closeCallCount
    }

    func hasPendingConnect() -> Bool {
        connectContinuation != nil
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
