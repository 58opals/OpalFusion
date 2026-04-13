// OpalFusion+Runtime+LiveTransport.swift

import CFNetwork
import Foundation
import Network
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
        private let host: String
        private let port: UInt16
        private let requiresTLS: Bool
        private let tlsTrustAnchorCertificateDERs: [Data]
        private let connectionQueue: DispatchQueue
        private let tlsVerificationQueue: DispatchQueue
        private var connection: NWConnection?
        private var connectContinuation: CheckedContinuation<Void, Error>?
        private var inboundContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation?
        private var waitingRestartTask: Task<Void, Never>?
        private var isReady: Bool
        private var isReceivePending: Bool
        private var isExplicitlyClosing: Bool

        init(
            host: String,
            port: UInt16,
            requiresTLS: Bool = false,
            tlsTrustAnchorCertificateDERs: [Data] = []
        ) {
            self.host = host
            self.port = port
            self.requiresTLS = requiresTLS
            self.tlsTrustAnchorCertificateDERs = tlsTrustAnchorCertificateDERs
            self.connectionQueue = DispatchQueue(label: "OpalFusion.Runtime.LivePrimaryTransport")
            self.tlsVerificationQueue = DispatchQueue(
                label: "OpalFusion.Runtime.LivePrimaryTransport.TLSVerify"
            )
            self.connection = nil
            self.connectContinuation = nil
            self.inboundContinuation = nil
            self.waitingRestartTask = nil
            self.isReady = false
            self.isReceivePending = false
            self.isExplicitlyClosing = false
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

            let connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: NWEndpoint.Port(rawValue: port)!,
                using: makeParameters()
            )
            self.connection = connection

            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Void, Error>) in
                self.connectContinuation = continuation
                connection.stateUpdateHandler = { state in
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
            connectContinuation?.resume(
                throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            )
            connectContinuation = nil
            waitingRestartTask?.cancel()
            waitingRestartTask = nil

            connection?.stateUpdateHandler = nil
            connection?.cancel()
            connection = nil
            isReady = false
            isReceivePending = false
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
            switch state {
            case .ready:
                waitingRestartTask?.cancel()
                waitingRestartTask = nil
                isReady = true
                connectContinuation?.resume()
                connectContinuation = nil
                if isReceivePending == false {
                    scheduleReceive()
                }
            case let .failed(error):
                handleTerminalState(error)
            case let .waiting(error):
                handleWaitingState(error)
            case .cancelled:
                if isExplicitlyClosing {
                    resetConnectionState()
                } else {
                    handleTerminalState(
                        OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
                    )
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
                inboundContinuation?.yield([UInt8](data))
            }

            if let error {
                handleTerminalState(error)
                return
            }

            if isComplete {
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

            waitingRestartTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard Task.isCancelled == false else {
                    return
                }

                await self.restartConnectionIfCurrent(connection, lastError: error)
            }
        }

        private func restartConnectionIfCurrent(
            _ expectedConnection: NWConnection,
            lastError: Error
        ) {
            defer {
                waitingRestartTask = nil
            }

            guard isExplicitlyClosing == false,
                  let connection,
                  connection === expectedConnection else {
                return
            }

            if connectContinuation == nil && inboundContinuation == nil {
                handleTerminalState(lastError)
                return
            }

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
            connection?.stateUpdateHandler = nil
            connection = nil
            connectContinuation = nil
            isReady = false
            isReceivePending = false
            isExplicitlyClosing = false
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
