// OpalFusion+Runtime+LivePrimaryTransport.swift

import CFNetwork
import Foundation
import Network
import OSLog
import Security

extension OpalFusion.Runtime {
    actor LivePrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
        typealias PrimaryConnectionBuilder = @Sendable (
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
        private let connectionFactory: PrimaryConnectionBuilder
        private var connection: (any OpalFusion.Runtime.PrimaryConnectioning)?
        private var eventTask: Task<Void, Never>?

        init(
            host: String,
            port: UInt16,
            requiresTLS: Bool = false,
            tlsTrustAnchorCertificateDERs: [Data] = [],
            restartDelay: Duration = .milliseconds(100),
            connectionFactory: @escaping PrimaryConnectionBuilder = {
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
                        "primary state waiting error=\(String(describing: error), privacy: .private)"
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
                        "primary terminal failure error=\(String(describing: error), privacy: .private)"
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
}
