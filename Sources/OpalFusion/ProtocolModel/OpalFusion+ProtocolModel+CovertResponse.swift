// OpalFusion+ProtocolModel+CovertResponse.swift

public extension OpalFusion.ProtocolModel {
    /// A top-level covert-channel response sent from the coordinator to a client.
    enum CovertResponse: Sendable, Equatable {
        case acknowledgement(OpalFusion.ProtocolModel.Acknowledgement)
        case serverFailure(OpalFusion.ProtocolModel.ServerFailure)
    }
}
