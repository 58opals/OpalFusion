// OpalFusion+Mosaic+OpalV0+CommitmentUniqueness.swift

import Foundation

extension OpalFusion.Mosaic.OpalV0 {
    static func validateCommitmentFieldUniqueness(
        _ commitments: [ComponentCommitment]
    ) throws {
        var saltedComponentDigests = Set<Data>()
        var amountCommitments = Set<Data>()
        var communicationPublicKeys = Set<Data>()

        for commitment in commitments {
            guard saltedComponentDigests.insert(
                Data(commitment.saltedComponentDigest)
            ).inserted else {
                throw WireContractError.duplicateSaltedComponentDigest
            }
            guard amountCommitments.insert(
                Data(commitment.amountCommitment)
            ).inserted else {
                throw WireContractError.duplicateAmountCommitment
            }
            guard communicationPublicKeys.insert(
                Data(commitment.communicationPublicKey)
            ).inserted else {
                throw WireContractError.duplicateCommunicationPublicKey
            }
        }
    }

    static func validateMainnetCommunicationEventIdentityUniqueness(
        _ commitments: [ComponentCommitment]
    ) throws {
        var eventIdentities = Set<Data>()
        for commitment in commitments {
            guard eventIdentities.insert(
                Data(commitment.communicationPublicKey.dropFirst())
            ).inserted else {
                throw WireContractError.duplicateCommunicationEventIdentity
            }
        }
    }
}
