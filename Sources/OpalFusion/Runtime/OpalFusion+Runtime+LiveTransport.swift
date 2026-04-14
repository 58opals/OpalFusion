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

    protocol PrimaryConnectioning: AnyObject {
        func setStateUpdateHandler(_ handler: (@Sendable (NWConnection.State) -> Void)?)
        func start(queue: DispatchQueue)
        func send(content: Data?, completion: NWConnection.SendCompletion)
        func receive(
            minimumIncompleteLength: Int,
            maximumLength: Int,
            completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
        )
        func restart()
        func cancel()
    }

    final class NetworkPrimaryConnection: PrimaryConnectioning {
        private let connection: NWConnection

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
        }

        func setStateUpdateHandler(_ handler: (@Sendable (NWConnection.State) -> Void)?) {
            connection.stateUpdateHandler = handler
        }

        func start(queue: DispatchQueue) {
            connection.start(queue: queue)
        }

        func send(content: Data?, completion: NWConnection.SendCompletion) {
            connection.send(
                content: content,
                completion: completion
            )
        }

        func receive(
            minimumIncompleteLength: Int,
            maximumLength: Int,
            completion: @escaping @Sendable (Data?, NWConnection.ContentContext?, Bool, NWError?) -> Void
        ) {
            connection.receive(
                minimumIncompleteLength: minimumIncompleteLength,
                maximumLength: maximumLength,
                completion: completion
            )
        }

        func restart() {
            connection.restart()
        }

        func cancel() {
            connection.cancel()
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
        private let connectionQueue: DispatchQueue
        private let tlsVerificationQueue: DispatchQueue
        private let restartDelay: Duration
        private let connectionFactory: PrimaryConnectionFactory
        private var connection: (any OpalFusion.Runtime.PrimaryConnectioning)?
        private var connectContinuation: CheckedContinuation<Void, Error>?
        private var inboundContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation?
        private var waitingRestartTask: Task<Void, Never>?
        private var lastNonCancellationTransportError: Error?
        private var isReady: Bool
        private var isReceivePending: Bool
        private var isExplicitlyClosing: Bool
        private var didObservePeerEOF: Bool

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
            self.connectionQueue = DispatchQueue(label: "OpalFusion.Runtime.LivePrimaryTransport")
            self.tlsVerificationQueue = DispatchQueue(
                label: "OpalFusion.Runtime.LivePrimaryTransport.TLSVerify"
            )
            self.restartDelay = restartDelay
            self.connectionFactory = connectionFactory
            self.connection = nil
            self.connectContinuation = nil
            self.inboundContinuation = nil
            self.waitingRestartTask = nil
            self.lastNonCancellationTransportError = nil
            self.isReady = false
            self.isReceivePending = false
            self.isExplicitlyClosing = false
            self.didObservePeerEOF = false
        }

        func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
            guard connection == nil else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted
            }

            let (stream, continuation) = AsyncThrowingStream.makeStream(
                of: [UInt8].self,
                throwing: Error.self
            )
            self.inboundContinuation = continuation
            self.isReady = false
            self.isReceivePending = false
            self.isExplicitlyClosing = false
            self.didObservePeerEOF = false
            self.lastNonCancellationTransportError = nil

            Self.logger.debug(
                "primary connect start host=\(self.host, privacy: .public) port=\(Int(self.port), privacy: .public) tls=\(self.requiresTLS, privacy: .public)"
            )

            let connection = connectionFactory(
                host,
                port,
                makeParameters()
            )
            self.connection = connection

            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                self.connectContinuation = continuation
                connection.setStateUpdateHandler { state in
                    Task {
                        await self.handleStateUpdate(state)
                    }
                }
                connection.start(queue: connectionQueue)
            }

            return stream
        }

        func write(_ bytes: [UInt8]) async throws {
            guard let connection, isReady else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
            }

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

        func close() async {
            isExplicitlyClosing = true
            didObservePeerEOF = false
            Self.logger.debug(
                "primary close explicit=true pendingConnect=\(self.connectContinuation != nil, privacy: .public)"
            )
            connectContinuation?.resume(
                throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            )
            connectContinuation = nil
            waitingRestartTask?.cancel()
            waitingRestartTask = nil

            connection?.setStateUpdateHandler(nil)
            connection?.cancel()
            connection = nil
            isReady = false
            isReceivePending = false
            lastNonCancellationTransportError = nil
            finishInbound(
                throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            )
            isExplicitlyClosing = false
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

        private func handleStateUpdate(
            _ state: NWConnection.State
        ) async {
            Self.logger.debug(
                "primary state transition state=\(Self.describe(state), privacy: .public)"
            )

            switch state {
            case .ready:
                waitingRestartTask?.cancel()
                waitingRestartTask = nil
                isReady = true
                lastNonCancellationTransportError = nil
                connectContinuation?.resume()
                connectContinuation = nil
                if isReceivePending == false {
                    scheduleReceive()
                }
            case let .failed(error):
                if connectContinuation != nil {
                    recordNonCancellationTransportError(error)
                }
                Self.logger.debug(
                    "primary state failed error=\(Self.describe(error), privacy: .public)"
                )
                handleTerminalState(error)
            case let .waiting(error):
                recordNonCancellationTransportError(error)
                Self.logger.debug(
                    "primary state waiting error=\(Self.describe(error), privacy: .public)"
                )
                handleWaitingState(error)
            case .cancelled:
                let pendingConnect = connectContinuation != nil
                let preservedStartupError = pendingConnect ? lastNonCancellationTransportError : nil
                Self.logger.debug(
                    "primary state cancelled explicit=\(self.isExplicitlyClosing, privacy: .public) pendingConnect=\(pendingConnect, privacy: .public) preservedError=\(Self.describeOptional(preservedStartupError), privacy: .public)"
                )
                if isExplicitlyClosing {
                    resetConnectionState()
                } else if didObservePeerEOF {
                    Self.logger.debug("primary state cancelled ignored reason=peer-eof")
                    resetConnectionState()
                } else {
                    handleTerminalState(resolveCancellationError())
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

            isReceivePending = true
            Self.logger.debug("primary receive scheduled")
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
                Self.logger.debug(
                    "primary receive bytes count=\(data.count, privacy: .public)"
                )
                inboundContinuation?.yield([UInt8](data))
            }

            if let error {
                Self.logger.debug(
                    "primary receive error error=\(Self.describe(error), privacy: .public)"
                )
                handleTerminalState(error)
                return
            }

            if isComplete {
                didObservePeerEOF = true
                Self.logger.debug(
                    "primary receive complete bytes=\(data?.count ?? 0, privacy: .public)"
                )
                finishInbound()
                resetConnectionState()
                return
            }

            scheduleReceive()
        }

        private func handleWaitingState(
            _ error: Error
        ) {
            guard isExplicitlyClosing == false else {
                return
            }

            isReady = false

            guard waitingRestartTask == nil, let connection else {
                return
            }

            let connectionID = ObjectIdentifier(connection)
            Self.logger.debug(
                "primary restart scheduled delayMs=\(Self.restartDelayMilliseconds(self.restartDelay), privacy: .public) error=\(Self.describe(error), privacy: .public)"
            )
            waitingRestartTask = Task {
                try? await Task.sleep(for: self.restartDelay)
                guard Task.isCancelled == false else {
                    return
                }

                self.restartConnectionIfCurrent(
                    connectionID,
                    lastError: error
                )
            }
        }

        private func restartConnectionIfCurrent(
            _ expectedConnectionID: ObjectIdentifier,
            lastError: Error
        ) {
            defer {
                waitingRestartTask = nil
            }

            guard isExplicitlyClosing == false else {
                Self.logger.debug("primary restart skipped reason=explicit-close")
                return
            }

            guard let connection else {
                Self.logger.debug("primary restart skipped reason=connection-missing")
                return
            }

            guard ObjectIdentifier(connection) == expectedConnectionID else {
                Self.logger.debug("primary restart skipped reason=connection-replaced")
                return
            }

            if connectContinuation == nil && inboundContinuation == nil {
                Self.logger.debug(
                    "primary restart skipped reason=no-active-consumer error=\(Self.describe(lastError), privacy: .public)"
                )
                handleTerminalState(lastError)
                return
            }

            Self.logger.debug("primary restart execute")
            connection.restart()
        }

        private func handleTerminalState(
            _ error: Error
        ) {
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            connectContinuation?.resume(throwing: error)
            connectContinuation = nil
            finishInbound(throwing: error)
            resetConnectionState()
        }

        private func recordNonCancellationTransportError(
            _ error: Error
        ) {
            guard isCancellationError(error) == false else {
                return
            }

            lastNonCancellationTransportError = error
        }

        private func resolveCancellationError() -> Error {
            guard connectContinuation != nil,
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

        private func finishInbound(
            throwing error: Error? = nil
        ) {
            guard let inboundContinuation else {
                return
            }

            self.inboundContinuation = nil
            if let error {
                inboundContinuation.finish(throwing: error)
            } else {
                inboundContinuation.finish()
            }
        }

        private func resetConnectionState() {
            waitingRestartTask?.cancel()
            waitingRestartTask = nil
            let connection = self.connection
            connection?.setStateUpdateHandler(nil)
            self.connection = nil
            connectContinuation = nil
            lastNonCancellationTransportError = nil
            isReady = false
            isReceivePending = false
            isExplicitlyClosing = false
            connection?.cancel()
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
                "waiting(\(describe(error)))"
            case let .failed(error):
                "failed(\(describe(error)))"
            case .cancelled:
                "cancelled"
            @unknown default:
                "unknown"
            }
        }

        private static func describe(
            _ error: Error
        ) -> String {
            String(describing: error)
        }

        private static func describeOptional(
            _ error: Error?
        ) -> String {
            guard let error else {
                return "none"
            }

            return describe(error)
        }

        private static func restartDelayMilliseconds(
            _ delay: Duration
        ) -> Int64 {
            let components = delay.components
            return components.seconds * 1_000 + Int64(components.attoseconds / 1_000_000_000_000_000)
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
