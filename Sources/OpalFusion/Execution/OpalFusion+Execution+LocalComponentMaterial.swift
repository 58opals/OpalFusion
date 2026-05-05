// OpalFusion+Execution+LocalComponentMaterial.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct LocalComponentMaterial: Sendable {
        let originalSlot: Int
        let payload: OpalFusion.Commitment.ComponentPayload
        let serializedComponent: [UInt8]
        let serializedInitialCommitment: [UInt8]
        let initialCommitment: OpalFusion.Commitment.InitialCommitment
        let proofMaterial: OpalFusion.Execution.UnassignedProofMaterial
        let communicationPrivateKey: [UInt8]
        let contributionSatoshis: Int64
    }
}
