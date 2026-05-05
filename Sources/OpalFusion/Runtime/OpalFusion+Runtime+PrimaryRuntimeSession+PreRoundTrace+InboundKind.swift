// OpalFusion+Runtime+PrimaryRuntimeSession+PreRoundTrace+InboundKind.swift

extension OpalFusion.Runtime.PrimaryRuntimeSession.PreRoundTrace {
    enum InboundKind: String, Sendable, Equatable {
        case serverHello = "ServerHello"
        case tierStatusUpdate = "TierStatusUpdate"
        case fusionBegin = "FusionBegin"
        case serverFailure = "ServerFailure"
    }
}
