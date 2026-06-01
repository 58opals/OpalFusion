// OpalFusion+Execution+ProductionWorkflow+InputOutpoint.swift

extension OpalFusion.Execution.ProductionWorkflow {
    struct InputOutpoint: Hashable {
        let transactionHash: [UInt8]
        let index: UInt32

        init(_ input: OpalFusion.Host.ParticipantInput) {
            self.transactionHash = input.outpointTransactionHashBytes
            self.index = input.outpointIndex
        }

        init(_ inputComponent: OpalFusion.Commitment.InputComponent) {
            self.transactionHash = inputComponent.outpointTransactionHash
            self.index = inputComponent.outpointIndex
        }
    }
}
