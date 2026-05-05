// OpalFusion+Runtime+PrimaryConnectionEvent.swift

import CFNetwork
import Foundation
import Network
import OSLog
import Security

extension OpalFusion.Runtime {
    enum PrimaryConnectionEvent: Sendable {
        case ready
        case waiting(any Error & Sendable)
        case received(Data)
        case peerEOF
        case failed(any Error & Sendable)
        case cancelled
    }
}
