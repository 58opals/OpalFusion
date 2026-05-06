// OpalFusion+Runtime+PrimaryRuntimeSession+PreRoundTrace+InboundKind.swift

extension OpalFusion.Runtime.PrimaryRuntimeSession.PreRoundTrace {
    enum InboundKind: String, Sendable, Equatable {
        case serverHello = "ServerHello"
        case tierStatusUpdate = "TierStatusUpdate"
        case fusionBegin = "FusionBegin"
        case startRound = "StartRound"
        case blindSignatureResponses = "BlindSignatureResponses"
        case allCommitments = "AllCommitments"
        case shareCovertComponents = "ShareCovertComponents"
        case fusionResult = "FusionResult"
        case theirProofsList = "TheirProofsList"
        case restartRound = "RestartRound"
        case serverFailure = "ServerFailure"

        init(message: OpalFusion.ProtocolModel.ServerMessage) {
            self = switch message {
            case .serverHello:
                .serverHello
            case .tierStatusUpdate:
                .tierStatusUpdate
            case .fusionBegin:
                .fusionBegin
            case .startRound:
                .startRound
            case .blindSignatureResponses:
                .blindSignatureResponses
            case .allCommitments:
                .allCommitments
            case .shareCovertComponents:
                .shareCovertComponents
            case .fusionResult:
                .fusionResult
            case .theirProofsList:
                .theirProofsList
            case .restartRound:
                .restartRound
            case .serverFailure:
                .serverFailure
            }
        }
    }
}
