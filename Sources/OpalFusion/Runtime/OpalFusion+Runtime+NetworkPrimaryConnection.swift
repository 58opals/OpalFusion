// OpalFusion+Runtime+NetworkPrimaryConnection.swift

import CFNetwork
import Foundation
import Network
import OpalDiagnostics
import Security

extension OpalFusion.Runtime {
    actor NetworkPrimaryConnection: PrimaryConnectioning {
        let connection: NWConnection
        let queue = DispatchQueue(
            label: "OpalFusion.Runtime.NetworkPrimaryConnection"
        )
        var eventContinuation: AsyncStream<
            OpalFusion.Runtime.PrimaryConnectionEvent
        >.Continuation?
        var readyContinuation: CheckedContinuation<Void, Error>?
        var waitingRestartTask: Task<Void, Never>?
        var lastNonCancellationTransportError: (any Error & Sendable)?
        var hasStarted: Bool
        var isReady: Bool
        var isReceivePending: Bool
        var isExplicitlyClosing: Bool
        var didObservePeerEOF: Bool

        init(
            host: String,
            port: UInt16,
            parameters: NWParameters
        ) throws {
            guard port > 0,
                  let endpointPort = NWEndpoint.Port(rawValue: port) else {
                throw OpalFusion.Runtime.LiveTransportError.invalidConfiguration(
                    "Primary connection port must be valid"
                )
            }
            self.connection = NWConnection(
                host: NWEndpoint.Host(host),
                port: endpointPort,
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




















    }
}
