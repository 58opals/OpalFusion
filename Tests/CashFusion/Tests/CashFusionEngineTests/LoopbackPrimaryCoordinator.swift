// LoopbackPrimaryCoordinator.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
import Foundation
import Network

actor LoopbackPrimaryCoordinator {
    let listener: NWListener
    let networkQueue: DispatchQueue
    var connection: NWConnection?
    var connectionReady: Bool
    var portValue: UInt16
    var frameDecoder: OpalFusion.Wire.PrimaryFrameDecoder
    let frameEncoder: OpalFusion.Wire.PrimaryFrameEncoder
    let messageEncoder: OpalFusion.Wire.PrimaryMessageEncoder
    let messageDecoder: OpalFusion.Wire.PrimaryMessageDecoder
    var clientMessages: [OpalFusion.ProtocolModel.ClientMessage]
    var clientMessageHistory: [OpalFusion.ProtocolModel.ClientMessage]
    var serverMessageHistory: [OpalFusion.ProtocolModel.ServerMessage]
    var messageWaiters: [
        (
            id: UUID,
            continuation: CheckedContinuation<OpalFusion.ProtocolModel.ClientMessage, Error>
        )
    ]
    var inboundError: Error?
    var startContinuation: CheckedContinuation<Void, Error>?
    var isStopping: Bool
    var forwardingProxy: CovertSocketTestServer?



    init(
        listener: NWListener,
        networkQueue: DispatchQueue,
        baseline: OpalFusion.Transport.BaselineConfiguration
    ) {
        self.listener = listener
        self.networkQueue = networkQueue
        self.connection = nil
        self.connectionReady = false
        self.portValue = 0
        self.frameDecoder = .init(configuration: baseline.framing)
        self.frameEncoder = .init(configuration: baseline.framing)
        self.messageEncoder = .init()
        self.messageDecoder = .init()
        self.clientMessages = []
        self.clientMessageHistory = []
        self.serverMessageHistory = []
        self.messageWaiters = []
        self.inboundError = nil
        self.startContinuation = nil
        self.isStopping = false
        self.forwardingProxy = nil
    }

    var port: UInt16 {
        portValue
    }

    func makeProxyConfiguration() async throws -> OpalFusion.Transport.TorSocks5Configuration {
        if forwardingProxy == nil {
            forwardingProxy = try await CovertSocketTestServer.start(proxyMode: .forward, tunnelPort: port)
        }
        return .init(host: "127.0.0.1", port: await forwardingProxy!.port)
    }



















    var recordedClientMessages: [OpalFusion.ProtocolModel.ClientMessage] {
        clientMessageHistory
    }

    var recordedServerMessages: [OpalFusion.ProtocolModel.ServerMessage] {
        serverMessageHistory
    }
}
