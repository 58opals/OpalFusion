// OpalFusion+Mosaic+OpalV0+ComponentCommitment.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalV0 {
    /// One canonical commitment disclosed in a contributor's grouped payload.
    struct ComponentCommitment: Sendable, Equatable {
        let saltedComponentDigest: [UInt8]
        let amountCommitment: [UInt8]
        let communicationPublicKey: [UInt8]

        init(
            saltedComponentDigest: [UInt8],
            amountCommitment: [UInt8],
            communicationPublicKey: [UInt8]
        ) throws {
            guard saltedComponentDigest.count
                == OpalFusion.Mosaic.OpalV0.digestByteCount else {
                throw WireContractError.invalidSaltedComponentDigestLength(
                    actual: saltedComponentDigest.count
                )
            }

            let validatedAmountCommitment: OpalCrypto.Pedersen.CommitmentPoint
            do {
                validatedAmountCommitment = try .init(
                    rawRepresentation: Data(amountCommitment)
                )
            } catch {
                throw WireContractError.invalidAmountCommitment
            }

            let validatedCommunicationPublicKey: OpalCrypto.Secp256k1.PublicKey
            do {
                validatedCommunicationPublicKey = try .init(
                    rawRepresentation: Data(communicationPublicKey)
                )
            } catch {
                throw WireContractError.invalidCommunicationPublicKey
            }

            self.saltedComponentDigest = Array(saltedComponentDigest)
            self.amountCommitment = [UInt8](
                validatedAmountCommitment.uncompressedRepresentation
            )
            self.communicationPublicKey = [UInt8](
                validatedCommunicationPublicKey.compressedRepresentation
            )
        }
    }
}
