// OpalFusion+Client+Diagnostics+HandshakeStage.swift

public extension OpalFusion.Client.Diagnostics {
    enum HandshakeStage: String, Sendable, Equatable {
        case notStarted
        case awaitingServerHello
        case awaitingFusionBegin
        case inRound
        case terminal
    }
}
