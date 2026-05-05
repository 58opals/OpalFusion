// OpalFusion+Runtime+PrimaryTransporting.swift

import CFNetwork
import Foundation
import Network
import OSLog
import Security

extension OpalFusion.Runtime {
    protocol PrimaryTransporting: Sendable {
        func connect() async throws -> AsyncThrowingStream<[UInt8], Error>
        func write(_ bytes: [UInt8]) async throws
        func close() async
    }
}
