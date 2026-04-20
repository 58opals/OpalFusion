// SessionTransportFactoryRecorder.swift

@testable import OpalFusion
import Foundation

final class SessionTransportFactoryRecorder: @unchecked Sendable {
    private let defaultPrimaryConnectError: Error?
    private let lock = NSLock()
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
        let connectError = lock.withLock { () -> Error? in
            if pendingPrimaryConnectErrors.isEmpty == false {
                return pendingPrimaryConnectErrors.removeFirst()
            }

            return defaultPrimaryConnectError
        }
        let transport = ScriptedPrimaryTransport(connectError: connectError)
        lock.withLock {
            primaryTransports.append(transport)
        }
        return transport
    }

    func makeCovert() -> any OpalFusion.Runtime.CovertTransporting {
        let transport = ScriptedCovertTransport()
        lock.lock()
        covertTransports.append(transport)
        lock.unlock()
        return transport
    }

    func primaryCount() -> Int {
        lock.withLock {
            primaryTransports.count
        }
    }
}
