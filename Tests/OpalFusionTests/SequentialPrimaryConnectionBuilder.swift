// SequentialPrimaryConnectionBuilder.swift

@testable import OpalFusion
import Foundation
import Network

final class SequentialPrimaryConnectionBuilder: @unchecked Sendable {
    private let lock = NSLock()
    private var connections: [any OpalFusion.Runtime.PrimaryConnectioning]

    init(connections: [any OpalFusion.Runtime.PrimaryConnectioning]) {
        self.connections = connections
    }

    func make(
        host _: String,
        port _: UInt16,
        parameters _: NWParameters
    ) -> any OpalFusion.Runtime.PrimaryConnectioning {
        lock.lock()
        defer {
            lock.unlock()
        }
        return connections.removeFirst()
    }
}
