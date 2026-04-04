// OpalFusion+ProtocolModel+CovertMessage.swift

public extension OpalFusion.ProtocolModel {
    /// A top-level covert-channel message sent from a client to the coordinator.
    enum CovertMessage: Sendable, Equatable {
        case component(OpalFusion.ProtocolModel.CovertComponent)
        case transactionSignature(OpalFusion.ProtocolModel.CovertTransactionSignature)
        case ping(OpalFusion.ProtocolModel.Ping)
    }
}
