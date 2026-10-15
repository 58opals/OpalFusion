import OpalFusionCore

// OpalFusion+Runtime+LiveCovertTransport.swift

import Foundation
import Network
import Security

extension OpalFusion.Runtime {
    actor LiveCovertTransport: CovertTransporting {
        private let torSocks5: OpalFusion.Transport.TorSocks5Configuration?
        private let tlsTrustAnchorCertificateDERs: [Data]
        private let tlsVerificationQueue = DispatchQueue(label: "OpalFusion.Covert.TLSVerify")
        private var generation = UUID()
        private var connections: [UUID: CovertSocketConnection] = [:]
        private(set) var currentEndpoint: CovertEndpointContext?

        init(
            torSocks5: OpalFusion.Transport.TorSocks5Configuration?,
            tlsTrustAnchorCertificateDERs: [Data] = []
        ) {
            self.torSocks5 = torSocks5
            self.tlsTrustAnchorCertificateDERs = tlsTrustAnchorCertificateDERs
        }

        func prepare(_ plan: CovertPreparationPlan) async throws {
            guard OpalFusion.Runtime.isValidHostName(plan.endpoint.host),
                  (1...UInt32(UInt16.max)).contains(plan.endpoint.port),
                  plan.endpoint.maxPayloadBytes > 0 else {
                throw LiveTransportError.malformedCovertEndpoint
            }
            guard let torSocks5,
                  OpalFusion.Runtime.isValidHostName(torSocks5.host),
                  torSocks5.port > 0,
                  torSocks5.resolvesCoordinatorHostNameRemotely else {
                throw LiveTransportError.invalidConfiguration("Valid Tor SOCKS5 configuration with remote DNS is required")
            }

            // Detach the old generation before suspension. Its completions and
            // cancellation handlers can only close the sockets they own.
            let previousConnections = Array(connections.values)
            connections.removeAll()
            generation = UUID()
            currentEndpoint = plan.endpoint
            for connection in previousConnections { await connection.cancel() }
        }

        func perform(_ request: CovertRequest) async throws -> [UInt8] {
            try Task.checkCancellation()
            guard currentEndpoint == request.endpoint else {
                throw LiveTransportError.covertEndpointNotPrepared
            }
            guard let torSocks5 else {
                throw LiveTransportError.invalidConfiguration("Tor SOCKS5 configuration is required")
            }
            let baselineFrame = OpalFusion.Transport.BaselineConfiguration.electronCash443.framing
            let framing = OpalFusion.Transport.FrameConfiguration(
                magicBytes: baselineFrame.magicBytes,
                maximumMessageLengthBytes: min(request.endpoint.maxPayloadBytes, baselineFrame.maximumMessageLengthBytes)
            )
            guard request.payload.count <= framing.maximumMessageLengthBytes else {
                throw LiveTransportError.covertPayloadTooLarge
            }
            let frame = try OpalFusion.Wire.PrimaryFrameEncoder(configuration: framing).encode(payload: request.payload)
            let timeout = request.startedAt.distance(to: request.deadline)
            guard timeout > .zero else { throw LiveTransportError.covertRequestTimedOut }

            // EC permits only one submission per connection per phase. Never
            // reuse a socket for another component or signature.
            let connectionID = UUID()
            let requestGeneration = generation
            let connection = CovertSocketConnection(
                host: torSocks5.host,
                port: torSocks5.port,
                parameters: makeParameters(for: request.endpoint, isolationID: connectionID)
            )
            connections[connectionID] = connection
            do {
                let response = try await withTaskCancellationHandler {
                    try await withThrowingTaskGroup(of: [UInt8].self) { group in
                        group.addTask { try await connection.exchange(frame, framing: framing) }
                        group.addTask {
                            try await Task.sleep(for: timeout)
                            throw LiveTransportError.covertRequestTimedOut
                        }
                        defer { group.cancelAll() }
                        return try await group.next()!
                    }
                } onCancel: {
                    Task { await connection.cancel() }
                }
                try Task.checkCancellation()
                guard generation == requestGeneration else { throw CancellationError() }
                // Retain successful sockets until the round's reset/close effect,
                // rather than signal individual submission completion by closing.
                return response
            } catch {
                connections.removeValue(forKey: connectionID)
                await connection.cancel()
                if case OpalFusion.Wire.PrimaryFrameError.payloadTooLarge = error {
                    throw LiveTransportError.covertResponsePayloadTooLarge
                }
                throw error
            }
        }

        func reset() async {
            let previousConnections = Array(connections.values)
            connections.removeAll()
            generation = UUID()
            currentEndpoint = nil
            for connection in previousConnections { await connection.cancel() }
        }

        private func makeParameters(for endpoint: CovertEndpointContext, isolationID: UUID) -> NWParameters {
            let tlsOptions: NWProtocolTLS.Options?
            if endpoint.requiresTLS == true {
                let options = NWProtocolTLS.Options()
                endpoint.host.withCString {
                    sec_protocol_options_set_tls_server_name(options.securityProtocolOptions, $0)
                }
                if !tlsTrustAnchorCertificateDERs.isEmpty {
                    let anchors = tlsTrustAnchorCertificateDERs
                    let host = endpoint.host
                    sec_protocol_options_set_verify_block(options.securityProtocolOptions, { _, trustReference, complete in
                        let trust = sec_trust_copy_ref(trustReference).takeRetainedValue()
                        let certificates = anchors.compactMap { SecCertificateCreateWithData(nil, $0 as CFData) }
                        guard certificates.count == anchors.count,
                              SecTrustSetAnchorCertificates(trust, certificates as CFArray) == errSecSuccess,
                              SecTrustSetAnchorCertificatesOnly(trust, true) == errSecSuccess,
                              SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess else {
                            complete(false)
                            return
                        }
                        complete(SecTrustEvaluateWithError(trust, nil))
                    }, tlsVerificationQueue)
                }
                tlsOptions = options
            } else {
                tlsOptions = nil
            }

            let parameters = NWParameters.tcp
            parameters.preferNoProxies = true
            parameters.defaultProtocolStack.applicationProtocols = [SOCKS5Framer.options(
                host: endpoint.host, port: UInt16(endpoint.port), isolationID: isolationID, tls: tlsOptions
            )]
            return parameters
        }
    }
}
