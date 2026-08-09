// OpalFusion+Mosaic+OpalV0+GroupedCommitmentPayload.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    /// One contributor's fixed 23-slot commitment document.
    struct GroupedCommitmentPayload: Sendable, Equatable {
        let profile: OpalFusion.Mosaic.Profile
        let commitments: [ComponentCommitment]
        let excessFeeSatoshis: UInt64
        let pedersenTotalNonce: [UInt8]

        init(
            profile: OpalFusion.Mosaic.Profile = .opalV0,
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
            switch profile {
            case .opalV0:
                guard excessFeeSatoshis == 0 else {
                    throw WireContractError.nonzeroExcessFee(
                        actual: excessFeeSatoshis
                    )
                }
            case .opalMainnetAlpha:
                let minimum = OpalFusion.Mosaic.OpalMainnetAlpha
                    .minimumExcessFeeSatoshis
                let maximum = OpalFusion.Mosaic.OpalMainnetAlpha
                    .maximumExcessFeeSatoshis
                guard (minimum ... maximum).contains(excessFeeSatoshis) else {
                    throw WireContractError.invalidExcessFee(
                        profile: profile,
                        minimum: minimum,
                        maximum: maximum,
                        actual: excessFeeSatoshis
                    )
                }
            case .draft1:
                throw WireContractError.unsupportedProfile(profile)
            }

            let validatedNonce: OpalCrypto.Pedersen.Nonce
            do {
                validatedNonce = try .init(
                    rawRepresentation: Data(pedersenTotalNonce)
                )
            } catch {
                throw WireContractError.invalidPedersenTotalNonce
            }

            self.profile = profile
            self.commitments = commitments
            self.excessFeeSatoshis = excessFeeSatoshis
            self.pedersenTotalNonce = [UInt8](validatedNonce.rawRepresentation)
        }
    }
}
