// OpalFusion+Execution+UnassignedProofMaterial.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct UnassignedProofMaterial: Sendable {
        let salt: [UInt8]
        let pedersenNonce: [UInt8]
    }
}
