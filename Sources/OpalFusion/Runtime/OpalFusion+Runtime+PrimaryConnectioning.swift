// OpalFusion+Runtime+PrimaryConnectioning.swift

import CFNetwork
import Foundation
import Network
import Security

extension OpalFusion.Runtime {
    protocol PrimaryConnectioning: Actor {
        func connect(
            restartDelay: Duration
        ) async throws -> AsyncStream<OpalFusion.Runtime.PrimaryConnectionEvent>
        func send(content: Data?) async throws
        func cancel() async
    }
}
