// OpalFusion+Execution+PlayerCommitMaterial.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct PlayerCommitMaterial: Sendable {
        let componentsByCommitmentOrder: [OpalFusion.Execution.LocalComponentMaterial]
        let blindSignatureRequests: [OpalCrypto.BlindSignature.Request]
        let pedersenTotalNonce: [UInt8]
        let excessFeeSatoshis: UInt64
        let randomNumber: [UInt8]
    }
}
