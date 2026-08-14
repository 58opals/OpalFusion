// MosaicMainnetAlphaPrivateManifestContractValidator.swift

import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha private manifest contract validation", .serialized)
struct MosaicMainnetAlphaPrivateManifestContractValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt

    @Test("Bind canonical nonce allocation relay pool and deadline documents")
    func bindCanonicalNonceAllocationRelayPoolAndDeadlineDocuments() throws {
        let formation = try MosaicPrivateDeploymentFixtures.makeFormation()
        let nonceAllocation = formation.nonceAllocation
        let shuffled = try Alpha.ContributorNonceAllocationDocument(
            roleElection: formation.roleElection,
            allocations: Array(nonceAllocation.allocations.reversed())
        )
        #expect(shuffled == nonceAllocation)
        #expect(
            try Alpha.ContributorNonceAllocationDocument.decode(
                from: nonceAllocation.canonicalBytes,
                roleElection: formation.roleElection
            ) == nonceAllocation
        )
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Alpha.ContributorNonceAllocationDocument.decode(
                from: nonceAllocation.canonicalBytes + [0],
                roleElection: formation.roleElection
            )
        }

        let validation = try MosaicPrivateDeploymentFixtures
            .makeManifestValidation(formation: formation)
        let core = validation.core

        #expect(
            validation.reservationLeaseExpirationUnixSeconds
                == core.deadlines.bchSigning
        )
        let context = try Alpha.ManifestProposalContext(
            roleElection: formation.roleElection,
            candidateSetDigest: core.candidateSetDigest,
            opaquePoolIdentifier: core.opaquePoolIdentifier
        )
        #expect(
            try Alpha.PreManifestDocumentCodec.decodeManifestProposal(
                from: Alpha.PreManifestDocumentCodec
                    .encodeManifestProposal(core),
                expectedContext: context
            ) == core
        )
    }

    @Test("Encode role and separate manifest signature bodies canonically")
    func encodeRoleAndSeparateManifestSignatureBodiesCanonically() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection(
            candidateCount: 7
        )
        let commitment = election.commitments[0]
        let reveal = election.reveals[0]
        let commitmentBytes = try Alpha.PreManifestDocumentCodec
            .encodeRoleCommitment(commitment)
        let revealBytes = try Alpha.PreManifestDocumentCodec
            .encodeRoleReveal(reveal)

        #expect(
            try Alpha.PreManifestDocumentCodec.decodeRoleCommitment(
                from: commitmentBytes,
                controlRoster: election.controlRoster
            ) == commitment
        )
        #expect(
            try Alpha.PreManifestDocumentCodec.decodeRoleReveal(
                from: revealBytes,
                controlRoster: election.controlRoster
            ) == reveal
        )
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Alpha.PreManifestDocumentCodec.decodeRoleReveal(
                from: revealBytes + [0],
                controlRoster: election.controlRoster
            )
        }

        let binding = try Attempt.ManifestBinding(
            validatedRoundIdentifier: [UInt8](repeating: 0x52, count: 32),
            validatedManifestDigest: [UInt8](repeating: 0x53, count: 32)
        )
        let signature = MosaicManifestSignatureFixtures.manifestSignature(
            signer: election.result.roster.controlIdentities[0],
            binding: binding
        )
        let signatureBytes = try Alpha.PreManifestDocumentCodec
            .encodeManifestSignature(signature)
        let decoded = try Alpha.PreManifestDocumentCodec
            .decodeManifestSignature(
                from: signatureBytes,
                for: binding,
                expectedRoster: election.result.roster
            )
        #expect(decoded.signature == signature)
        #expect(decoded.validation.signer == signature.signer)
        #expect(decoded.validation.binding == binding)
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Alpha.PreManifestDocumentCodec.decodeManifestSignature(
                from: signatureBytes + [0],
                for: binding,
                expectedRoster: election.result.roster
            )
        }
    }

    @Test("Reject nonce allocation reuse and incomplete membership")
    func rejectNonceAllocationReuseAndIncompleteMembership() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection(
            candidateCount: 7
        )
        let valid = try makeNonceAllocation(election: election)
        #expect(throws: (any Error).self) {
            _ = try Alpha.ContributorNonceAllocationDocument(
                roleElection: election.result,
                allocations: Array(valid.allocations.dropLast())
            )
        }
        var duplicateSource = valid.allocations
        duplicateSource[1] = .init(
            contributor: duplicateSource[1].contributor,
            appGeneratedPublicSource: duplicateSource[0].publicSource
        )
        #expect(
            throws: Alpha.ContributorNonceAllocationDocument.ValidationError
                .duplicatePublicSource
        ) {
            _ = try Alpha.ContributorNonceAllocationDocument(
                roleElection: election.result,
                allocations: duplicateSource
            )
        }
        var duplicateContributor = valid.allocations
        duplicateContributor[1] = .init(
            contributor: duplicateContributor[0].contributor,
            appGeneratedPublicSource: duplicateContributor[1].publicSource
        )
        #expect(throws: (any Error).self) {
            _ = try Alpha.ContributorNonceAllocationDocument(
                roleElection: election.result,
                allocations: duplicateContributor
            )
        }
    }

    private func makeNonceAllocation(
        election: MosaicRoleElectionFixtures.Election
    ) throws -> Alpha.ContributorNonceAllocationDocument {
        let allocations = election.result.roster.contributors.enumerated().map {
            index, contributor in
            Alpha.ContributorNonceAllocationDocument.ContributorAllocationEntry(
                contributor: contributor,
                appGeneratedPublicSource: [UInt8](
                    repeating: UInt8(index + 1),
                    count: 32
                )
            )
        }
        return try .init(
            roleElection: election.result,
            allocations: allocations
        )
    }
}
