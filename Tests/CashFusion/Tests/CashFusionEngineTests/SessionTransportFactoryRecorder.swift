// SessionTransportFactoryRecorder.swift

@testable import CashFusionEngine
@testable import OpalFusionCore
actor SessionTransportFactoryRecorder {
    private let defaultPrimaryConnectError: Error?
    private let blocksFirstPrimaryClose: Bool
    private var primaryTransports: [ScriptedPrimaryTransport] = []
    private var covertTransports: [ScriptedCovertTransport] = []
    private var pendingPrimaryConnectErrors: [Error?]

    init(primaryConnectError: Error? = nil, blocksFirstPrimaryClose: Bool = false) {
        self.defaultPrimaryConnectError = primaryConnectError
        self.blocksFirstPrimaryClose = blocksFirstPrimaryClose
        self.pendingPrimaryConnectErrors = []
    }

    init(primaryConnectErrors: [Error?]) {
        self.defaultPrimaryConnectError = primaryConnectErrors.last ?? nil
        self.blocksFirstPrimaryClose = false
        self.pendingPrimaryConnectErrors = primaryConnectErrors
    }

    func makePrimary() -> any OpalFusion.Runtime.PrimaryTransporting {
        let connectError: Error?
        if pendingPrimaryConnectErrors.isEmpty == false {
            connectError = pendingPrimaryConnectErrors.removeFirst()
        } else {
            connectError = defaultPrimaryConnectError
        }
        let transport = ScriptedPrimaryTransport(
            connectError: connectError,
            blocksClose: blocksFirstPrimaryClose && primaryTransports.isEmpty
        )
        primaryTransports.append(transport)
        return transport
    }

    func makeCovert() -> any OpalFusion.Runtime.CovertTransporting {
        let transport = ScriptedCovertTransport()
        covertTransports.append(transport)
        return transport
    }

    var primaryTransportCount: Int {
        primaryTransports.count
    }

    func primaryTransport(at index: Int) -> ScriptedPrimaryTransport? {
        guard primaryTransports.indices.contains(index) else {
            return nil
        }

        return primaryTransports[index]
    }
}
