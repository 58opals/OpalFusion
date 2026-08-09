// MosaicMainnetAlphaContributionFeeValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha contribution fees")
struct MosaicMainnetAlphaContributionFeeValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    @Test(
        "Allocate the fixed ten-satoshi overhead in canonical contributor order",
        arguments: [6, 7, 8]
    )
    func allocateFixedOverhead(contributorCount: Int) throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection(
            candidateCount: contributorCount + 1
        )
        let orderedContributors = election.result.roster.contributors.sorted {
            $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
        }
        let shares = try orderedContributors.map {
            try Alpha.ContributionFeePolicy.requiredExcessFeeSatoshis(
                for: $0,
                in: election.result.roster
            )
        }
        let baseShare = Alpha.fixedTransactionOverheadByteCount
            / contributorCount
        let remainder = Alpha.fixedTransactionOverheadByteCount
            % contributorCount
        let expected = (0 ..< contributorCount).map {
            UInt64(baseShare + ($0 < remainder ? 1 : 0))
        }

        #expect(shares == expected)
        #expect(shares.reduce(0, +) == 10)
        #expect(shares.allSatisfy { (1 ... 2).contains($0) })
    }

    @Test("Match component contributions to the exact final transaction fee")
    func matchFinalTransactionFee() throws {
        let input = try OpalV0.InputComponent(
            previousTransactionHash: [UInt8](repeating: 0x11, count: 32),
            outputIndex: 0,
            amountSatoshis: 1_000
        )
        let output = try OpalV0.OutputComponent(
            lockingScript: [0x76, 0xA9, 0x14]
                + [UInt8](repeating: 0x22, count: 20)
                + [0x88, 0xAC],
            amountSatoshis: 815
        )
        let inputContribution = Alpha.ContributionFeePolicy
            .contributionSatoshis(for: .input(input))
        let outputContribution = Alpha.ContributionFeePolicy
            .contributionSatoshis(for: .output(output))

        #expect(inputContribution == 859)
        #expect(outputContribution == -849)
        #expect(inputContribution + outputContribution == 10)
        #expect(
            try Alpha.ContributionFeePolicy.expectedFinalFeeSatoshis(
                inputCount: 1,
                outputCount: 1
            ) == 185
        )
        #expect(input.amountSatoshis - output.amountSatoshis == 185)
        #expect(
            Alpha.ContributionFeePolicy.contributionSatoshis(for: .blank) == 0
        )
    }

    @Test("Reject conductor, foreign contributor, and impossible component counts")
    func rejectInvalidFeeInputs() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        #expect(
            throws: Alpha.ContributionFeePolicy.ValidationError
                .conductorCannotContribute
        ) {
            _ = try Alpha.ContributionFeePolicy.requiredExcessFeeSatoshis(
                for: election.result.roster.conductor,
                in: election.result.roster
            )
        }
        let foreignContributor = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 10
        )
        #expect(
            throws: Alpha.ContributionFeePolicy.ValidationError
                .unknownContributor
        ) {
            _ = try Alpha.ContributionFeePolicy.requiredExcessFeeSatoshis(
                for: foreignContributor,
                in: election.result.roster
            )
        }
        #expect(
            throws: Alpha.ContributionFeePolicy.ValidationError
                .invalidComponentCounts(inputs: 0, outputs: 1)
        ) {
            _ = try Alpha.ContributionFeePolicy.expectedFinalFeeSatoshis(
                inputCount: 0,
                outputCount: 1
            )
        }
        #expect(
            throws: Alpha.ContributionFeePolicy.ValidationError
                .invalidComponentCounts(inputs: 184, outputs: 1)
        ) {
            _ = try Alpha.ContributionFeePolicy.expectedFinalFeeSatoshis(
                inputCount: 184,
                outputCount: 1
            )
        }
        #expect(
            throws: Alpha.ContributionFeePolicy.ValidationError
                .invalidComponentCounts(inputs: .max, outputs: .max)
        ) {
            _ = try Alpha.ContributionFeePolicy.expectedFinalFeeSatoshis(
                inputCount: .max,
                outputCount: .max
            )
        }
    }

    @Test("Bind grouped commitments to the selected profile fee range")
    func bindGroupedCommitmentProfile() throws {
        let commitments = try (0 ..< Alpha.componentCountPerContributor).map(
            MosaicOpalV0WireContractValidator.makeCommitment
        )
        let nonce = [UInt8](repeating: 0, count: 31) + [0x01]
        #expect(
            throws: OpalV0.WireContractError.invalidExcessFee(
                profile: .opalMainnetAlpha,
                minimum: 1,
                maximum: 2,
                actual: 0
            )
        ) {
            _ = try OpalV0.GroupedCommitmentPayload(
                profile: .opalMainnetAlpha,
                commitments: commitments,
                excessFeeSatoshis: 0,
                pedersenTotalNonce: nonce
            )
        }
        #expect(
            throws: OpalV0.WireContractError.invalidExcessFee(
                profile: .opalMainnetAlpha,
                minimum: 1,
                maximum: 2,
                actual: 3
            )
        ) {
            _ = try OpalV0.GroupedCommitmentPayload(
                profile: .opalMainnetAlpha,
                commitments: commitments,
                excessFeeSatoshis: 3,
                pedersenTotalNonce: nonce
            )
        }
        #expect(
            try OpalV0.GroupedCommitmentPayload(
                profile: .opalMainnetAlpha,
                commitments: commitments,
                excessFeeSatoshis: 1,
                pedersenTotalNonce: nonce
            ).profile == .opalMainnetAlpha
        )
    }

    @Test("Seal an exact manifest-bound grouped Pedersen balance")
    func validatePlayerCommitSemantics() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let contributor = election.result.roster.contributors.sorted {
            $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
        }[0]
        let requiredExcess = try Alpha.ContributionFeePolicy
            .requiredExcessFeeSatoshis(
                for: contributor,
                in: election.result.roster
            )
        let playerCommit = try makePlayerCommit(
            contributor: contributor,
            roundIdentifier: manifest.core.roundIdentifier,
            excessFeeSatoshis: requiredExcess
        )
        let validation = try Alpha.PlayerCommitSemanticValidation(
            validating: playerCommit,
            against: manifest
        )

        #expect(validation.manifestBinding == manifest.binding)
        #expect(validation.contributor == contributor)
        #expect(validation.playerCommitDigest == playerCommit.digest)
        #expect(validation.requiredExcessFeeSatoshis == requiredExcess)
    }

    @Test("Reject wrong fee, Pedersen balance, round, role, and contributor")
    func rejectInvalidPlayerCommitSemantics() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let orderedContributors = election.result.roster.contributors.sorted {
            $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
        }
        let contributor = orderedContributors[0]
        let requiredExcess = try Alpha.ContributionFeePolicy
            .requiredExcessFeeSatoshis(
                for: contributor,
                in: election.result.roster
            )
        let wrongExcess: UInt64 = requiredExcess == 1 ? 2 : 1
        let wrongFee = try makePlayerCommit(
            contributor: contributor,
            roundIdentifier: manifest.core.roundIdentifier,
            excessFeeSatoshis: wrongExcess
        )
        #expect(
            throws: Alpha.PlayerCommitSemanticValidation.ValidationError
                .excessFeeMismatch(
                    expected: requiredExcess,
                    actual: wrongExcess
                )
        ) {
            _ = try Alpha.PlayerCommitSemanticValidation(
                validating: wrongFee,
                against: manifest
            )
        }

        let wrongBalance = try makePlayerCommit(
            contributor: contributor,
            roundIdentifier: manifest.core.roundIdentifier,
            excessFeeSatoshis: requiredExcess,
            totalNonceOverride: Data(repeating: 0, count: 31) + Data([0x7F])
        )
        #expect(
            throws: Alpha.PlayerCommitSemanticValidation.ValidationError
                .pedersenBalanceMismatch
        ) {
            _ = try Alpha.PlayerCommitSemanticValidation(
                validating: wrongBalance,
                against: manifest
            )
        }

        let wrongRound = try makePlayerCommit(
            contributor: contributor,
            roundIdentifier: [UInt8](repeating: 0xEE, count: 32),
            excessFeeSatoshis: requiredExcess
        )
        #expect(
            throws: Alpha.PlayerCommitSemanticValidation.ValidationError
                .roundMismatch
        ) {
            _ = try Alpha.PlayerCommitSemanticValidation(
                validating: wrongRound,
                against: manifest
            )
        }

        let conductorCommit = try makePlayerCommit(
            contributor: election.result.roster.conductor,
            roundIdentifier: manifest.core.roundIdentifier,
            excessFeeSatoshis: 1
        )
        #expect(
            throws: Alpha.PlayerCommitSemanticValidation.ValidationError
                .conductorCannotContribute
        ) {
            _ = try Alpha.PlayerCommitSemanticValidation(
                validating: conductorCommit,
                against: manifest
            )
        }

        let foreignContributor = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 10
        )
        let foreignCommit = try makePlayerCommit(
            contributor: foreignContributor,
            roundIdentifier: manifest.core.roundIdentifier,
            excessFeeSatoshis: 1
        )
        #expect(
            throws: Alpha.PlayerCommitSemanticValidation.ValidationError
                .unknownContributor
        ) {
            _ = try Alpha.PlayerCommitSemanticValidation(
                validating: foreignCommit,
                against: manifest
            )
        }

        let setup = try OpalCrypto.Pedersen.Setup()
        let cancellingNonces = try (1 ... 22).map { scalar in
            try OpalCrypto.Pedersen.Nonce(
                rawRepresentation: Data(
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(scalar)
                )
            )
        } + [
            try OpalCrypto.Pedersen.Nonce(
                rawRepresentation: Data(
                    MosaicOpalV0WireContractValidator.bytes(
                        hexadecimal:
                            "fffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364044"
                    )
                )
            )
        ]
        let cancellingCommitments = try cancellingNonces.enumerated().map {
            index, nonce in
            let commitment = try setup.commit(amount: 0, nonce: nonce)
            let communicationKey = try OpalCrypto.Secp256k1.derivePublicKey(
                from: .init(
                    rawRepresentation: Data(
                        MosaicUnsignedTransactionTranscriptFixtures
                            .indexedDigest(2_000 + index)
                    )
                )
            )
            return try OpalV0.ComponentCommitment(
                saltedComponentDigest:
                    MosaicUnsignedTransactionTranscriptFixtures
                        .indexedDigest(50_000 + index),
                amountCommitment: [UInt8](
                    commitment.point.uncompressedRepresentation
                ),
                communicationPublicKey: [UInt8](
                    communicationKey.compressedRepresentation
                )
            )
        }
        let infinityCommit = try Alpha.PlayerCommit(
            roundIdentifier: manifest.core.roundIdentifier,
            contributor: contributor,
            groupedCommitment: try .init(
                profile: .opalMainnetAlpha,
                commitments: cancellingCommitments,
                excessFeeSatoshis: requiredExcess,
                pedersenTotalNonce:
                    MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(1)
            ),
            authorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests()
        )
        #expect(
            throws: Alpha.PlayerCommitSemanticValidation.ValidationError
                .invalidPedersenMaterial
        ) {
            _ = try Alpha.PlayerCommitSemanticValidation(
                validating: infinityCommit,
                against: manifest
            )
        }
    }

    @Test("Reject an Opal v0 grouped commitment inside a mainnet PlayerCommit")
    func rejectCrossProfileGroupedCommitment() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        #expect(
            throws: Alpha.ContractError.groupedCommitmentProfileMismatch(.opalV0)
        ) {
            _ = try Alpha.PlayerCommit(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                contributor: election.result.roster.contributors[0],
                groupedCommitment: MosaicOpalV0WireContractValidator
                    .makeGroupedCommitment(),
                authorizationRequests: MosaicMainnetAlphaFixtures
                    .makeAuthorizationRequests()
            )
        }
    }

    private func makePlayerCommit(
        contributor: Attempt.ControlIdentity,
        roundIdentifier: [UInt8],
        excessFeeSatoshis: UInt64,
        totalNonceOverride: Data? = nil
    ) throws -> Alpha.PlayerCommit {
        try .init(
            roundIdentifier: roundIdentifier,
            contributor: contributor,
            groupedCommitment: makeBalancedGroupedCommitment(
                excessFeeSatoshis: excessFeeSatoshis,
                totalNonceOverride: totalNonceOverride
            ),
            authorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests()
        )
    }

    private func makeBalancedGroupedCommitment(
        excessFeeSatoshis: UInt64,
        totalNonceOverride: Data?
    ) throws -> OpalV0.GroupedCommitmentPayload {
        let setup = try OpalCrypto.Pedersen.Setup()
        let pedersenCommitments = try (0 ..< Alpha.componentCountPerContributor)
            .map { index in
                try setup.commit(
                    amount: index == 0 ? Int64(excessFeeSatoshis) : 0,
                    nonce: .init(
                        rawRepresentation: Data(repeating: 0, count: 31)
                            + Data([UInt8(index + 1)])
                    )
                )
            }
        let combined = try setup.combine(pedersenCommitments)
        let commitments = try pedersenCommitments.enumerated().map {
            index, commitment in
            let communicationKey = try OpalCrypto.Secp256k1.derivePublicKey(
                from: .init(
                    rawRepresentation: Data(repeating: 0, count: 31)
                        + Data([UInt8(index + 64)])
                )
            )
            return try OpalV0.ComponentCommitment(
                saltedComponentDigest: [UInt8](repeating: 0, count: 30)
                    + [UInt8(index >> 8), UInt8(truncatingIfNeeded: index)],
                amountCommitment: [UInt8](
                    commitment.point.uncompressedRepresentation
                ),
                communicationPublicKey: [UInt8](
                    communicationKey.compressedRepresentation
                )
            )
        }
        return try .init(
            profile: .opalMainnetAlpha,
            commitments: commitments,
            excessFeeSatoshis: excessFeeSatoshis,
            pedersenTotalNonce: [UInt8](
                totalNonceOverride ?? combined.nonce.rawRepresentation
            )
        )
    }
}
