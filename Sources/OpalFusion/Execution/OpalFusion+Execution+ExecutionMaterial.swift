// OpalFusion+Execution+ExecutionMaterial.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct ExecutionMaterial: Sendable {
        var playerCommitMaterial: OpalFusion.Execution.PlayerCommitMaterial?
        var finalizedBlindSignatures: [[UInt8]]
        var sharedRoundMaterial: OpalFusion.Execution.SharedRoundMaterial?
        var covertSignatureMessages: [OpalFusion.ProtocolModel.CovertMessage]?
        var covertSignatureSourceTransaction: [UInt8]?

        init() {
            self.playerCommitMaterial = nil
            self.finalizedBlindSignatures = []
            self.sharedRoundMaterial = nil
            self.covertSignatureMessages = nil
            self.covertSignatureSourceTransaction = nil
        }
    }
}
