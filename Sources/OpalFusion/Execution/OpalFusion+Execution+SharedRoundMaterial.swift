// OpalFusion+Execution+SharedRoundMaterial.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct SharedRoundMaterial: Sendable {
        let allCommitmentBytes: [[UInt8]]
        let allComponentBytes: [[UInt8]]
        let sessionHash: [UInt8]
        let decodedComponents: [OpalFusion.Execution.DecodedComponent]
        let myCommitmentIndices: [Int]
        let myComponentIndices: [Int]
        let transactionTemplate: OpalFusion.Execution.BCHTransaction
        let transactionInputComponentIndices: [Int]
        let localInputReferences: [OpalFusion.Execution.LocalInputReference]
    }
}
