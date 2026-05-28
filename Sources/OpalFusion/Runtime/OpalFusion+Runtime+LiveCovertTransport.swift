// OpalFusion+Runtime+LiveCovertTransport.swift

import CFNetwork
import Foundation
import Network
import Security

extension OpalFusion.Runtime {
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

            let proxyConfiguration = makeProxyConfiguration()
            configuration.connectionProxyDictionary = proxyConfiguration
            self.proxyConfiguration = proxyConfiguration

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

            guard request.payload.count <= request.endpoint.maxPayloadBytes else {
                throw OpalFusion.Runtime.LiveTransportError.covertPayloadTooLarge
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

            guard let response = response as? HTTPURLResponse else {
                throw OpalFusion.Runtime.LiveTransportError.invalidHTTPResponse
            }

            if (200 ..< 300).contains(response.statusCode) == false {
                throw OpalFusion.Runtime.LiveTransportError.unexpectedHTTPStatus(response.statusCode)
            }

            guard data.count <= request.endpoint.maxPayloadBytes else {
                throw OpalFusion.Runtime.LiveTransportError.covertResponsePayloadTooLarge
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
            guard OpalFusion.Runtime.isValidHostName(endpoint.host) else {
                throw OpalFusion.Runtime.LiveTransportError.malformedCovertURL
            }

            guard (1 ... UInt32(UInt16.max)).contains(endpoint.port) else {
                throw OpalFusion.Runtime.LiveTransportError.malformedCovertURL
            }

            guard OpalFusion.Runtime.validateCovertEntryPath(endpoint.entryPath) == nil else {
                throw OpalFusion.Runtime.LiveTransportError.malformedCovertURL
            }

            var components = URLComponents()
            components.scheme = endpoint.requiresTLS == true ? "https" : "http"
            components.host = Self.makeURLComponentsHost(from: endpoint.host)
            components.port = Int(endpoint.port)
            components.path = endpoint.entryPath

            guard let url = components.url else {
                throw OpalFusion.Runtime.LiveTransportError.malformedCovertURL
            }

            return url
        }

        private static func makeURLComponentsHost(from host: String) -> String {
            host.contains(":") ? "[\(host)]" : host
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
