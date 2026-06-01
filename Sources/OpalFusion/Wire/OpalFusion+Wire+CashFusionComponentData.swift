// OpalFusion+Wire+CashFusionComponentData.swift

extension OpalFusion.Wire {
    struct CashFusionComponentData: Sendable, Equatable {
        let saltCommitment: [UInt8]
        let payload: OpalFusion.Commitment.ComponentPayload?

        init(
            saltCommitment: [UInt8],
            payload: OpalFusion.Commitment.ComponentPayload?
        ) {
            self.saltCommitment = saltCommitment
            self.payload = payload
        }
    }
}
