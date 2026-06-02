// OpalFusion+Runtime+LivePrimaryTransport.swift

import CFNetwork
import Foundation
import Network
import OpalDiagnostics
import Security

extension OpalFusion.Runtime {
    actor LivePrimaryTransport: OpalFusion.Runtime.PrimaryTransporting {
        typealias PrimaryConnectionBuilder = @Sendable (
            String,
            UInt16,
            NWParameters
        ) throws -> any OpalFusion.Runtime.PrimaryConnectioning

        let host: String
        let port: UInt16
        let requiresTLS: Bool
        let tlsTrustAnchorCertificateDERs: [Data]
        let tlsVerificationQueue: DispatchQueue
        let restartDelay: Duration
        let connectionFactory: PrimaryConnectionBuilder
        var connection: (any OpalFusion.Runtime.PrimaryConnectioning)?
        var eventTask: Task<Void, Never>?

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
                try OpalFusion.Runtime.NetworkPrimaryConnection(
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







    }
}
