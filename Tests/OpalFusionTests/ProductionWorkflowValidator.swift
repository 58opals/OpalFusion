// ProductionWorkflowValidator.swift

@testable import OpalFusion
import Foundation
import OpalCrypto
import Testing

struct ProductionWorkflowValidator {





















}

extension ProductionWorkflowValidator {
    static func serializedComponent(
        saltCommitment: [UInt8],
        payload: OpalFusion.Commitment.ComponentPayload
    ) throws -> [UInt8] {
        try OpalFusion.Wire.CashFusionComponentCodec.encode(
            payload: payload,
            saltCommitment: saltCommitment
        )
    }

    static func saltCommitment(_ byte: UInt8) -> [UInt8] {
        [UInt8](repeating: byte, count: 32)
    }
}
