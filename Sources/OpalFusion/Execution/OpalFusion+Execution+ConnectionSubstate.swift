// OpalFusion+Execution+ConnectionSubstate.swift

import OpalCrypto

extension OpalFusion.Execution {
    enum ConnectionSubstate: String, Sendable, Equatable {
        case disconnected
        case awaitingServerHello
        case awaitingFusionBegin
        case inRound
        case failed
    }
}
