// OpalFusion+Mosaic+OpalMainnetAlpha+PlayerCommitSemanticValidation.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Sealed proof that one PlayerCommit satisfies the manifest's contributor and
    /// grouped Pedersen fee rules. Component-opening linkage remains a later gate.
    struct PlayerCommitSemanticValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case roundMismatch
            case unknownContributor
            case conductorCannotContribute
            case excessFeeMismatch(expected: UInt64, actual: UInt64)
            case invalidPedersenMaterial
            case pedersenBalanceMismatch
        }

        let manifestBinding: OpalFusion.Mosaic.Attempt.ManifestBinding
        let contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
        let playerCommitDigest: [UInt8]
        let requiredExcessFeeSatoshis: UInt64

        init(
            validating playerCommit: PlayerCommit,
            against manifest: RoundManifest
        ) throws(ValidationError) {
            let setup: OpalCrypto.Pedersen.Setup
            do {
                setup = try .init()
            } catch {
                throw .invalidPedersenMaterial
            }
            guard playerCommit.roundIdentifier == manifest.core.roundIdentifier else {
                throw .roundMismatch
            }
            guard playerCommit.contributor != manifest.core.roster.conductor else {
                throw .conductorCannotContribute
            }
            guard manifest.core.roster.contributors.contains(
                playerCommit.contributor
            ) else {
                throw .unknownContributor
            }

            let requiredExcessFeeSatoshis: UInt64
            do {
                requiredExcessFeeSatoshis = try ContributionFeePolicy
                    .requiredExcessFeeSatoshis(
                        for: playerCommit.contributor,
                        in: manifest.core.roster
                    )
            } catch {
                throw .unknownContributor
            }
            guard playerCommit.groupedCommitment.excessFeeSatoshis
                == requiredExcessFeeSatoshis else {
                throw .excessFeeMismatch(
                    expected: requiredExcessFeeSatoshis,
                    actual: playerCommit.groupedCommitment.excessFeeSatoshis
                )
            }

            let commitmentPoints: [OpalCrypto.Pedersen.CommitmentPoint]
            let totalNonce: OpalCrypto.Pedersen.Nonce
            do {
                commitmentPoints = try playerCommit.groupedCommitment
                    .commitments.map {
                        try .init(rawRepresentation: Data($0.amountCommitment))
                    }
                totalNonce = try .init(
                    rawRepresentation: Data(
                        playerCommit.groupedCommitment.pedersenTotalNonce
                    )
                )
            } catch {
                throw .invalidPedersenMaterial
            }

            let actualTotal: OpalCrypto.Pedersen.CommitmentPoint
            let expectedTotal: OpalCrypto.Pedersen.CommitmentPoint
            do {
                actualTotal = try OpalCrypto.Pedersen.Setup.addPoints(
                    commitmentPoints
                )
                expectedTotal = try setup.commit(
                    amount: Int64(requiredExcessFeeSatoshis),
                    nonce: totalNonce
                ).point
            } catch {
                throw .invalidPedersenMaterial
            }
            guard actualTotal == expectedTotal else {
                throw .pedersenBalanceMismatch
            }

            self.manifestBinding = manifest.binding
            self.contributor = playerCommit.contributor
            self.playerCommitDigest = playerCommit.digest
            self.requiredExcessFeeSatoshis = requiredExcessFeeSatoshis
        }
    }
}
