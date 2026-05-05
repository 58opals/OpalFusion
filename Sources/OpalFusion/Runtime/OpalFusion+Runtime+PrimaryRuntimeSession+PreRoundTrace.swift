// OpalFusion+Runtime+PrimaryRuntimeSession+PreRoundTrace.swift

extension OpalFusion.Runtime.PrimaryRuntimeSession {
    struct PreRoundTrace: Sendable, Equatable {
        var lastInboundKind: InboundKind?
        var lastInboundPayloadBytes: Int?
        var sawServerHello: Bool
        var wroteClientHello: Bool
        var wroteJoinPools: Bool
        var handshakeStage: OpalFusion.Client.Diagnostics.HandshakeStage
        var recentEvents: [OpalFusion.Client.Diagnostics.Event]

        init() {
            self.lastInboundKind = nil
            self.lastInboundPayloadBytes = nil
            self.sawServerHello = false
            self.wroteClientHello = false
            self.wroteJoinPools = false
            self.handshakeStage = .notStarted
            self.recentEvents = []
        }
    }
}
