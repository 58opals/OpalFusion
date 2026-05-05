// SessionTransportFactoryRecorder.swift

@testable import OpalFusion

actor SessionTransportFactoryRecorder {
    private let defaultPrimaryConnectError: Error?
    private var primaryTransports: [ScriptedPrimaryTransport] = []
    private var covertTransports: [ScriptedCovertTransport] = []
    private var pendingPrimaryConnectErrors: [Error?]

    init(primaryConnectError: Error? = nil) {
        self.defaultPrimaryConnectError = primaryConnectError
        self.pendingPrimaryConnectErrors = []
    }

    init(primaryConnectErrors: [Error?]) {
        self.defaultPrimaryConnectError = primaryConnectErrors.last ?? nil
        self.pendingPrimaryConnectErrors = primaryConnectErrors
    }

    func makePrimary() -> any OpalFusion.Runtime.PrimaryTransporting {
        let connectError: Error?
        if pendingPrimaryConnectErrors.isEmpty == false {
            connectError = pendingPrimaryConnectErrors.removeFirst()
        } else {
            connectError = defaultPrimaryConnectError
        }
        let transport = ScriptedPrimaryTransport(connectError: connectError)
        primaryTransports.append(transport)
        return transport
    }

    func makeCovert() -> any OpalFusion.Runtime.CovertTransporting {
        let transport = ScriptedCovertTransport()
        covertTransports.append(transport)
        return transport
    }

    func primaryCount() -> Int {
        primaryTransports.count
    }

    func primaryTransport(at index: Int) -> ScriptedPrimaryTransport? {
        guard primaryTransports.indices.contains(index) else {
            return nil
        }

        return primaryTransports[index]
    }
}
