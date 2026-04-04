// OpalFusion+Runtime+LiveTransport.swift

import CFNetwork
import Darwin
import Foundation

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
        private let socketQueue: DispatchQueue
        private var socketFileDescriptor: Int32?
        private var inboundContinuation: AsyncThrowingStream<[UInt8], Error>.Continuation?

        init(
            host: String,
            port: UInt16
        ) {
            self.host = host
            self.port = port
            self.socketQueue = DispatchQueue(label: "OpalFusion.Runtime.LivePrimaryTransport")
            self.socketFileDescriptor = nil
            self.inboundContinuation = nil
        }

        func connect() async throws -> AsyncThrowingStream<[UInt8], Error> {
            guard socketFileDescriptor == nil else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionAlreadyStarted
            }

            let socketFileDescriptor = try connectSocket()
            self.socketFileDescriptor = socketFileDescriptor

            let (stream, continuation) = AsyncThrowingStream.makeStream(
                of: [UInt8].self,
                throwing: Error.self
            )
            self.inboundContinuation = continuation

            socketQueue.async { [socketFileDescriptor] in
                var buffer = [UInt8](repeating: 0, count: 65_536)

                while true {
                    let bytesRead = Darwin.recv(
                        socketFileDescriptor,
                        &buffer,
                        buffer.count,
                        0
                    )

                    if bytesRead > 0 {
                        continuation.yield(Array(buffer[..<Int(bytesRead)]))
                        continue
                    }

                    if bytesRead == 0 {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: POSIXError(.ENOTCONN))
                    }
                    break
                }
            }

            return stream
        }

        func write(_ bytes: [UInt8]) async throws {
            guard let socketFileDescriptor else {
                throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
            }

            let sent = bytes.withUnsafeBytes { buffer in
                Darwin.send(
                    socketFileDescriptor,
                    buffer.baseAddress,
                    buffer.count,
                    0
                )
            }

            guard sent == bytes.count else {
                throw POSIXError(.ENOTCONN)
            }
        }

        func close() async {
            if let socketFileDescriptor {
                Darwin.shutdown(socketFileDescriptor, SHUT_RDWR)
                Darwin.close(socketFileDescriptor)
                self.socketFileDescriptor = nil
            }
            inboundContinuation?.finish(
                throwing: OpalFusion.Runtime.LiveTransportError.primaryConnectionCancelled
            )
            inboundContinuation = nil
        }

        private func connectSocket() throws -> Int32 {
            var hints = addrinfo(
                ai_flags: AI_ADDRCONFIG,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: IPPROTO_TCP,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var results: UnsafeMutablePointer<addrinfo>?
            let portString = String(port)

            guard getaddrinfo(host, portString, &hints, &results) == 0 else {
                throw OpalFusion.Runtime.LiveTransportError.invalidConfiguration(
                    "Coordinator host or port could not be resolved"
                )
            }

            defer {
                freeaddrinfo(results)
            }

            var cursor = results
            while let info = cursor {
                let socketFileDescriptor = socket(
                    info.pointee.ai_family,
                    info.pointee.ai_socktype,
                    info.pointee.ai_protocol
                )
                if socketFileDescriptor >= 0 {
                    if Darwin.connect(
                        socketFileDescriptor,
                        info.pointee.ai_addr,
                        info.pointee.ai_addrlen
                    ) == 0 {
                        return socketFileDescriptor
                    }

                    Darwin.close(socketFileDescriptor)
                }

                cursor = info.pointee.ai_next
            }

            throw OpalFusion.Runtime.LiveTransportError.primaryConnectionNotReady
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
