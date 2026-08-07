// OpalFusion+Mosaic+OpalV0+GroupedCommitmentPayload.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    /// One contributor's fixed 23-slot commitment document.
    struct GroupedCommitmentPayload: Sendable, Equatable {
        let commitments: [ComponentCommitment]
        let excessFeeSatoshis: UInt64
        let pedersenTotalNonce: [UInt8]

        init(
            commitments: [ComponentCommitment],
            excessFeeSatoshis: UInt64,
            pedersenTotalNonce: [UInt8]
        ) throws {
            guard commitments.count
                == OpalFusion.Mosaic.OpalV0.componentAuthorizationCountPerContributor else {
                throw WireContractError.invalidGroupedCommitmentCount(
                    actual: commitments.count
                )
            }
            for index in commitments.indices {
                guard commitments[..<index].contains(commitments[index]) == false else {
                    throw WireContractError.duplicateGroupedCommitment
                }
            }
            try OpalFusion.Mosaic.OpalV0.validateCommitmentFieldUniqueness(
                commitments
            )
            guard excessFeeSatoshis == 0 else {
                throw WireContractError.nonzeroExcessFee(
                    actual: excessFeeSatoshis
                )
            }

            let validatedNonce: OpalCrypto.Pedersen.Nonce
            do {
                validatedNonce = try .init(
                    rawRepresentation: Data(pedersenTotalNonce)
                )
            } catch {
                throw WireContractError.invalidPedersenTotalNonce
            }

            self.commitments = commitments
            self.excessFeeSatoshis = excessFeeSatoshis
            self.pedersenTotalNonce = [UInt8](validatedNonce.rawRepresentation)
        }
    }
}
