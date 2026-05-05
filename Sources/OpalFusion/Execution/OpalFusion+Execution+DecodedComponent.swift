// OpalFusion+Execution+DecodedComponent.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct DecodedComponent: Sendable {
        let serializedComponent: [UInt8]
        let saltCommitment: [UInt8]
        let payload: OpalFusion.Commitment.ComponentPayload
    }
}
