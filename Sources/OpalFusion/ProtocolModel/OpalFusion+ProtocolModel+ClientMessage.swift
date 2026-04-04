// OpalFusion+ProtocolModel+ClientMessage.swift

public extension OpalFusion.ProtocolModel {
    /// A top-level primary-channel message sent from a client to the coordinator.
    enum ClientMessage: Sendable, Equatable {
        case clientHello(OpalFusion.ProtocolModel.ClientHello)
        case joinPools(OpalFusion.ProtocolModel.JoinPools)
        case playerCommit(OpalFusion.ProtocolModel.PlayerCommit)
        case myProofsList(OpalFusion.ProtocolModel.MyProofsList)
        case blames(OpalFusion.ProtocolModel.Blames)
    }
}
