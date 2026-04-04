// OpalFusion+ProtocolModel+ServerMessage.swift

public extension OpalFusion.ProtocolModel {
    /// A top-level primary-channel message sent from the coordinator to a client.
    enum ServerMessage: Sendable, Equatable {
        case serverHello(OpalFusion.ProtocolModel.ServerHello)
        case tierStatusUpdate(OpalFusion.ProtocolModel.TierStatusUpdate)
        case fusionBegin(OpalFusion.ProtocolModel.FusionBegin)
        case startRound(OpalFusion.ProtocolModel.StartRound)
        case blindSignatureResponses(OpalFusion.ProtocolModel.BlindSignatureResponses)
        case allCommitments(OpalFusion.ProtocolModel.AllCommitments)
        case shareCovertComponents(OpalFusion.ProtocolModel.ShareCovertComponents)
        case fusionResult(OpalFusion.ProtocolModel.FusionResult)
        case theirProofsList(OpalFusion.ProtocolModel.TheirProofsList)
        case restartRound(OpalFusion.ProtocolModel.RestartRound)
        case serverFailure(OpalFusion.ProtocolModel.ServerFailure)
    }
}
