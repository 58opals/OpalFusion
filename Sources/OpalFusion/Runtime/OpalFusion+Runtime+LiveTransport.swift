// OpalFusion+Runtime+LiveTransport.swift

import CFNetwork
import Foundation
import Network
import OSLog
import Security

extension OpalFusion.Runtime {
    protocol PrimaryTransporting: Sendable {
        func connect() async throws -> AsyncThrowingStream<[UInt8], Error>
        func write(_ bytes: [UInt8]) async throws
        func close() async
    }

    protocol CovertTransporting: Sendable {
        func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws
        func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8]
        func reset() async
    }

    struct CovertProxyConfigurationSnapshot: Sendable, Equatable {
        let socksEnabled: Bool
        let proxyHost: String?
        let proxyPort: Int?
    }

    enum PrimaryConnectionEvent: Sendable {
        case ready
        case waiting(any Error & Sendable)
        case received(Data)
        case peerEOF
        case failed(any Error & Sendable)
        case cancelled
    }

    protocol PrimaryConnectioning: Actor {
        func connect(
            restartDelay: Duration
        ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent>
        func send(content: Data?) async throws
        func cancel() async
    }

    actor NetworkPrimaryConnection: PrimaryConnectioning {
        private static let logger = Logger(
            subsystem: "OpalFusion",
            category: "NetworkPrimaryConnection"
        )
        private let connection: NWConnection
        private let queue = DispatchQueue(
            label: "OpalFusion.Runtime.NetworkPrimaryConnection"
        )
        private var eventContinuation: AsyncStream<
            OpalFusion.Runtime.PrimaryConnectionEvent
        >.Continuation?
        private var readyContinuation: CheckedContinuation<Void, Error>?
        private var waitingRestartTask: Task<Void, Never>?
        private var lastNonCancellationTransportError: (any Error & Sendable)?
        private var hasStarted: Bool
        private var isReady: Bool
        private var isReceivePending: Bool
        private var isExplicitlyClosing: Bool
        private var didObservePeerEOF: Bool

        init(
            host: String,
            port: UInt16,
            parameters: NWParameters
        ) {
            self.connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: parameters
            )
            self.eventContinuation = nil
            self.readyContinuation = nil
            self.waitingRestartTask = nil
            self.lastNonCancellationTransportError = nil
            self.hasStarted = false
            self.isReady = false
            self.isReceivePending = false
            self.isExplicitlyClosing = false
            self.didObservePeerEOF = false
        }

        func connect(
            restartDelay: Duration
        ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent> {
            guard hasStarted == false else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted
            }

            hasStarted = true
            isReady = false
            isReceivePending = false
            isExplicitlyClosing = false
            didObservePeerEOF = false
            lastNonCancellationTransportError = nil

            let eventStream = makeEventStream()
            connection.stateUpdateHandler = { state in
                Task {
                    await self.handleStateUpdate(
                        state,
                        restartDelay: restartDelay
                    )
                }
            }

            do {
                try await withCheckedThrowingContinuation {
                    (continuation: CheckedContinuation<Void, Error>) in
                    self.readyContinuation = continuation
                    connection.start(queue: queue)
                }
            } catch {
                finishEvents()
                throw error
            }

            return eventStream
        }

        func send(content: Data?) async throws {
            guard isReady else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
            }

            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                connection.send(
                    content: content,
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

        func cancel() async {
            isExplicitlyClosing = true
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            readyContinuation?.resume(
                throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            )
            readyContinuation = nil
            connection.cancel()
        }

        private func makeEventStream() -> AsyncStream<
            OpalFusion.Runtime.PrimaryConnectionEvent
        > {
            var capturedContinuation: AsyncStream<
                OpalFusion.Runtime.PrimaryConnectionEvent
            >.Continuation?
            let eventStream = AsyncStream(bufferingPolicy: .unbounded) { continuation in
                capturedContinuation = continuation
            }
            self.eventContinuation = capturedContinuation
            return eventStream
        }

        private func handleStateUpdate(
            _ state: NWConnection.State,
            restartDelay: Duration
        ) async {
            Self.logger.debug(
                "state transition state=\(Self.describe(state), privacy: .public)"
            )
            switch state {
            case .ready:
                waitingRestartTask?.cancel()
                waitingRestartTask = nil
                isReady = true
                lastNonCancellationTransportError = nil
                eventContinuation?.yield(.ready)
                readyContinuation?.resume()
                readyContinuation = nil
                if isReceivePending == false {
                    scheduleReceive()
                }
            case let .failed(error):
                if readyContinuation != nil {
                    recordNonCancellationTransportError(error)
                }
                handleTerminalFailure(error)
            case let .waiting(error):
                recordNonCancellationTransportError(error)
                handleWaitingState(
                    error,
                    restartDelay: restartDelay
                )
            case .cancelled:
                if isExplicitlyClosing {
                    handleCancellation()
                } else if didObservePeerEOF {
                    resetState(cancelUnderlying: false)
                } else {
                    handleTerminalFailure(resolveCancellationError())
                }
            case .setup, .preparing:
                break
            @unknown default:
                break
            }
        }

        private func scheduleReceive() {
            isReceivePending = true
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
        ) async {
            isReceivePending = false

            if let data, data.isEmpty == false {
                eventContinuation?.yield(.received(data))
            }

            if let error {
                if isExplicitlyClosing && isCancellationError(error) {
                    return
                }
                handleTerminalFailure(error)
                return
            }

            if isComplete {
                didObservePeerEOF = true
                eventContinuation?.yield(.peerEOF)
                finishEvents()
                resetState(cancelUnderlying: true)
                return
            }

            scheduleReceive()
        }

        private func handleWaitingState(
            _ error: NWError,
            restartDelay: Duration
        ) {
            guard isExplicitlyClosing == false else {
                return
            }

            isReady = false
            eventContinuation?.yield(.waiting(error))

            guard shouldRestartAfterWaiting(error) else {
                handleTerminalFailure(error)
                return
            }

            guard waitingRestartTask == nil else {
                return
            }

            waitingRestartTask = Task {
                try? await Task.sleep(for: restartDelay)
                guard Task.isCancelled == false else {
                    return
                }

                self.restartConnectionIfNeeded(
                    lastError: error
                )
            }
        }

        private func restartConnectionIfNeeded(
            lastError: NWError
        ) {
            defer {
                waitingRestartTask = nil
            }

            guard isExplicitlyClosing == false else {
                return
            }

            if readyContinuation == nil && eventContinuation == nil {
                handleTerminalFailure(lastError)
                return
            }

            connection.restart()
        }

        private func handleTerminalFailure(
            _ error: any Error & Sendable
        ) {
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            readyContinuation?.resume(throwing: error)
            readyContinuation = nil
            eventContinuation?.yield(.failed(error))
            finishEvents()
            resetState(cancelUnderlying: true)
        }

        private func handleCancellation() {
            eventContinuation?.yield(.cancelled)
            finishEvents()
            resetState(cancelUnderlying: false)
        }

        private func recordNonCancellationTransportError(
            _ error: any Error & Sendable
        ) {
            guard isCancellationError(error) == false else {
                return
            }

            lastNonCancellationTransportError = error
        }

        private func resolveCancellationError() -> any Error & Sendable {
            guard readyContinuation != nil,
                  let lastNonCancellationTransportError else {
                return OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            }

            return lastNonCancellationTransportError
        }

        private func isCancellationError(
            _ error: Error
        ) -> Bool {
            if let transportError = error as? OpalFusion.Runtime.LiveTransportError,
               transportError == .primaryConnectionCancelled {
                return true
            }

            if let networkError = error as? NWError,
               case let .posix(code) = networkError,
               code == .ECANCELED {
                return true
            }

            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain,
               nsError.code == Int(ECANCELED) {
                return true
            }

            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorCancelled {
                return true
            }

            return false
        }

        private func shouldRestartAfterWaiting(
            _ error: NWError
        ) -> Bool {
            switch error {
            case .tls:
                false
            case .dns, .posix, .wifiAware:
                true
            @unknown default:
                true
            }
        }

        private static func describe(
            _ state: NWConnection.State
        ) -> String {
            switch state {
            case .setup:
                "setup"
            case .preparing:
                "preparing"
            case .ready:
                "ready"
            case let .waiting(error):
                "waiting(\(String(describing: error)))"
            case let .failed(error):
                "failed(\(String(describing: error)))"
            case .cancelled:
                "cancelled"
            @unknown default:
                "unknown"
            }
        }

        private func finishEvents() {
            guard let eventContinuation else {
                return
            }

            self.eventContinuation = nil
            eventContinuation.finish()
        }

        private func resetState(
            cancelUnderlying: Bool
        ) {
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            connection.stateUpdateHandler = nil
            if cancelUnderlying {
                connection.cancel()
            }
            readyContinuation = nil
            lastNonCancellationTransportError = nil
            isReady = false
            isReceivePending = false
            isExplicitlyClosing = false
            didObservePeerEOF = false
        }
    }

    enum LiveTransportError: LocalizedError, Sendable, Equatable {
        case invalidConfiguration(String)
        case primaryConnectionAlreadyStarted
        case primaryConnectionNotReady
        case primaryConnectionCancelled
        case covertEndpointNotPrepared
        case malformedCovertURL
        case unexpectedHTTPStatus(Int)

        var errorDescription: String? {
            switch self {
            case let .invalidConfiguration(summary):
                summary
            case .primaryConnectionAlreadyStarted:
                "Primary connection was already started"
            case .primaryConnectionNotReady:
                "Primary connection is not ready"
            case .primaryConnectionCancelled:
                "Primary connection was cancelled"
            case .covertEndpointNotPrepared:
                "Covert endpoint was not prepared"
            case .malformedCovertURL:
                "Covert request URL could not be constructed"
            case let .unexpectedHTTPStatus(statusCode):
                "Covert request failed with HTTP status \(statusCode)"
            }
        }
    }

    static func validateConfiguration(
        _ configuration: OpalFusion.Client.Configuration
    ) -> String? {
        if configuration.coordinatorHost.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Coordinator host must not be empty"
        }

        if configuration.coordinatorPort == 0 {
            return "Coordinator port must be greater than zero"
        }

        if configuration.covertChannel.entryPath.isEmpty ||
            configuration.covertChannel.entryPath.hasPrefix("/") == false {
            return "Covert entry path must start with /"
        }

        if configuration.covertChannel.maxPayloadBytes <= 0 {
            return "Covert max payload bytes must be greater than zero"
        }

        if configuration.covertChannel.requestTimeoutMilliseconds == 0 {
            return "Covert request timeout must be greater than zero"
        }

        if let torSocks5 = configuration.torSocks5 {
            if torSocks5.host.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return "Tor SOCKS5 host must not be empty"
            }

            if torSocks5.port == 0 {
                return "Tor SOCKS5 port must be greater than zero"
            }
        }

        return nil
    }

    actor LivePrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
        typealias PrimaryConnectionFactory = @Sendable (
            String,
            UInt16,
            NWParameters
        ) -> any OpalFusion.Runtime.PrimaryConnectioning

        private static let logger = Logger(
            subsystem: "OpalFusion",
            category: "LivePrimaryTransport"
        )

        private let host: String
        private let port: UInt16
        private let requiresTLS: Bool
        private let tlsTrustAnchorCertificateDERs: [Data]
        private let tlsVerificationQueue: DispatchQueue
        private let restartDelay: Duration
        private let connectionFactory: PrimaryConnectionFactory
        private var connection: (any OpalFusion.Runtime.PrimaryConnectioning)?
        private var eventTask: Task<Void, Never>?

        init(
            host: String,
            port: UInt16,
            requiresTLS: Bool = false,
            tlsTrustAnchorCertificateDERs: [Data] = [],
            restartDelay: Duration = .milliseconds(100),
            connectionFactory: @escaping PrimaryConnectionFactory = {
                host,
                port,
                parameters in
                OpalFusion.Runtime.NetworkPrimaryConnection(
                    host: host,
                    port: port,
                    parameters: parameters
                )
            }
        ) {
            self.host = host
            self.port = port
            self.requiresTLS = requiresTLS
            self.tlsTrustAnchorCertificateDERs = tlsTrustAnchorCertificateDERs
            self.tlsVerificationQueue = DispatchQueue(
                label: "OpalFusion.Runtime.LivePrimaryTransport.TLSVerify"
            )
            self.restartDelay = restartDelay
            self.connectionFactory = connectionFactory
            self.connection = nil
            self.eventTask = nil
        }

        func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
            guard connection == nil else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted
            }

            let (inboundStream, inboundContinuation) = AsyncThrowingStream.makeStream(
                of: [UInt8].self,
                throwing: Error.self
            )

            Self.logger.debug(
                "primary connect start host=\(self.host, privacy: .public) port=\(Int(self.port), privacy: .public) tls=\(self.requiresTLS, privacy: .public)"
            )

            let connection = connectionFactory(
                host,
                port,
                makeParameters()
            )
            let connectionID = ObjectIdentifier(connection as AnyObject)
            self.connection = connection
            do {
                let eventStream = try await connection.connect(
                    restartDelay: restartDelay
                )
                let eventTask = Task { [eventStream, inboundContinuation] in
                    await self.pumpConnectionEvents(
                        eventStream,
                        into: inboundContinuation,
                        for: connectionID
                    )
                }
                self.eventTask = eventTask
                return inboundStream
            } catch {
                clearConnectionIfCurrent(connectionID)
                throw error
            }
        }

        func write(_ bytes: [UInt8]) async throws {
            guard let connection else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
            }

            try await connection.send(content: Data(bytes))
        }

        func close() async {
            guard let connection else {
                return
            }

            await connection.cancel()
            let eventTask = self.eventTask
            _ = await eventTask?.result
        }

        private func pumpConnectionEvents(
            _ eventStream: AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent>,
            into inboundStream: AsyncThrowingStream<[UInt8], Error>.Continuation,
            for connectionID: ObjectIdentifier
        ) async {
            for await event in eventStream {
                switch event {
                case .ready:
                    Self.logger.debug("primary state transition state=ready")
                case let .waiting(error):
                    Self.logger.debug(
                        "primary state waiting error=\(String(describing: error), privacy: .public)"
                    )
                case let .received(data):
                    Self.logger.debug(
                        "primary receive bytes count=\(data.count, privacy: .public)"
                    )
                    inboundStream.yield([UInt8](data))
                case .peerEOF:
                    Self.logger.debug("primary receive complete bytes=0")
                    inboundStream.finish()
                    clearConnectionIfCurrent(connectionID)
                    return
                case let .failed(error):
                    Self.logger.debug(
                        "primary terminal failure error=\(String(describing: error), privacy: .public)"
                    )
                    inboundStream.finish(throwing: error)
                    clearConnectionIfCurrent(connectionID)
                    return
                case .cancelled:
                    Self.logger.debug("primary state transition state=cancelled")
                    inboundStream.finish(
                        throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
                    )
                    clearConnectionIfCurrent(connectionID)
                    return
                }
            }

            inboundStream.finish()
            clearConnectionIfCurrent(connectionID)
        }

        private func clearConnectionIfCurrent(
            _ expectedConnectionID: ObjectIdentifier
        ) {
            guard let connection else {
                return
            }

            guard ObjectIdentifier(connection as AnyObject) == expectedConnectionID else {
                return
            }

            self.connection = nil
            self.eventTask = nil
        }

        private func makeParameters() -> NWParameters {
            guard requiresTLS else {
                return .tcp
            }

            let tlsOptions = NWProtocolTLS.Options()
            let securityOptions = tlsOptions.securityProtocolOptions

            host.withCString { serverName in
                sec_protocol_options_set_tls_server_name(securityOptions, serverName)
            }

            if tlsTrustAnchorCertificateDERs.isEmpty == false {
                let pinnedCertificateDERs = Set(self.tlsTrustAnchorCertificateDERs)
                sec_protocol_options_set_verify_block(
                    securityOptions,
                    { _, trustReference, complete in
                        let trust = sec_trust_copy_ref(trustReference).takeRetainedValue()
                        let certificateChain = SecTrustCopyCertificateChain(trust) as? [SecCertificate] ?? []
                        for certificate in certificateChain {
                            let certificateDER = SecCertificateCopyData(certificate) as Data
                            if pinnedCertificateDERs.contains(certificateDER) {
                                complete(true)
                                return
                            }
                        }

                        complete(false)
                    },
                    tlsVerificationQueue
                )
            }

            return NWParameters(
                tls: tlsOptions,
                tcp: NWProtocolTCP.Options()
            )
        }
    }

    actor LiveCovertTransport: OpalFusion.Runtime.CovertTransporting {
        private let torSocks5: OpalFusion.Transport.TorSocks5Configuration?
        private let sessionFactory: @Sendable (URLSessionConfiguration) -> URLSession
        private let requestExecutor: @Sendable (URLSession, URLRequest) async throws -> (Data, URLResponse)
        private(set) var currentEndpoint: OpalFusion.Runtime.CovertEndpointContext?
        private(set) var proxyConfiguration: [AnyHashable: Any]?
        private var session: URLSession?

        init(
            torSocks5: OpalFusion.Transport.TorSocks5Configuration?,
            sessionFactory: @escaping @Sendable (URLSessionConfiguration) -> URLSession = {
                URLSession(configuration: $0)
            },
            requestExecutor: @escaping @Sendable (URLSession, URLRequest) async throws -> (Data, URLResponse) = {
                session, request in
                try await session.data(for: request)
            }
        ) {
            self.torSocks5 = torSocks5
            self.sessionFactory = sessionFactory
            self.requestExecutor = requestExecutor
            self.currentEndpoint = nil
            self.proxyConfiguration = nil
            self.session = nil
        }

        func prepare(_ plan: OpalFusion.Runtime.CovertPreparationPlan) async throws {
            let timeoutSeconds = Self.timeInterval(
                from: plan.startedAt.distance(to: plan.deadline),
                minimumMilliseconds: 1
            )
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = timeoutSeconds
            configuration.timeoutIntervalForResource = timeoutSeconds
            configuration.waitsForConnectivity = false

            if let proxyConfiguration = makeProxyConfiguration() {
                configuration.connectionProxyDictionary = proxyConfiguration
                self.proxyConfiguration = proxyConfiguration
            } else {
                self.proxyConfiguration = nil
            }

            session?.invalidateAndCancel()
            session = sessionFactory(configuration)
            currentEndpoint = plan.endpoint
        }

        func perform(_ request: OpalFusion.Runtime.CovertRequest) async throws -> [UInt8] {
            guard currentEndpoint == request.endpoint else {
                throw OpalFusion.Runtime.LiveTransportError.covertEndpointNotPrepared
            }

            guard let session else {
                throw OpalFusion.Runtime.LiveTransportError.covertEndpointNotPrepared
            }

            let timeoutSeconds = Self.timeInterval(
                from: request.startedAt.distance(to: request.deadline),
                minimumMilliseconds: 1
            )
            let url = try makeURL(for: request.endpoint)
            var urlRequest = URLRequest(url: url, timeoutInterval: timeoutSeconds)
            urlRequest.httpMethod = "POST"
            urlRequest.httpBody = Data(request.payload)
            urlRequest.setValue("application/octet-stream", forHTTPHeaderField: "Content-Type")

            let (data, response) = try await requestExecutor(session, urlRequest)

            if let response = response as? HTTPURLResponse,
               (200 ..< 300).contains(response.statusCode) == false {
                throw OpalFusion.Runtime.LiveTransportError.unexpectedHTTPStatus(response.statusCode)
            }

            return [UInt8](data)
        }

        func reset() async {
            session?.invalidateAndCancel()
            session = nil
            currentEndpoint = nil
            proxyConfiguration = nil
        }

        func proxyConfigurationSnapshot() -> OpalFusion.Runtime.CovertProxyConfigurationSnapshot {
            .init(
                socksEnabled: (proxyConfiguration?[kCFNetworkProxiesSOCKSEnable as String] as? Int) == 1,
                proxyHost: proxyConfiguration?[kCFNetworkProxiesSOCKSProxy as String] as? String,
                proxyPort: proxyConfiguration?[kCFNetworkProxiesSOCKSPort as String] as? Int
            )
        }

        private func makeURL(
            for endpoint: OpalFusion.Runtime.CovertEndpointContext
        ) throws -> URL {
            var components = URLComponents()
            components.scheme = endpoint.requiresTLS == true ? "https" : "http"
            components.host = endpoint.host
            components.port = Int(endpoint.port)
            components.path = endpoint.entryPath

            guard let url = components.url else {
                throw OpalFusion.Runtime.LiveTransportError.malformedCovertURL
            }

            return url
        }

        private func makeProxyConfiguration() -> [AnyHashable: Any]? {
            guard let torSocks5 else {
                return nil
            }

            return [
                kCFNetworkProxiesSOCKSEnable as String: 1,
                kCFNetworkProxiesSOCKSProxy as String: torSocks5.host,
                kCFNetworkProxiesSOCKSPort as String: Int(torSocks5.port)
            ]
        }

        private static func timeInterval(
            from duration: Duration,
            minimumMilliseconds: Int64
        ) -> TimeInterval {
            let milliseconds = max(duration.wholeMilliseconds, minimumMilliseconds)
            return TimeInterval(milliseconds) / 1_000
        }
    }
}
