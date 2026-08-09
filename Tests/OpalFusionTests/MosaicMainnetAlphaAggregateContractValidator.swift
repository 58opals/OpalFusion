// MosaicMainnetAlphaAggregateContractValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha aggregate contracts")
struct MosaicMainnetAlphaAggregateContractValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Codec = Alpha.CanonicalWireCodec
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0

    @Test("Freeze the complete per-contributor authorization-response set")
    func freezeAuthorizationResponseSet() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let preparation = try makePreparation(election: election)
        let playerCommits = try makePlayerCommits(
            election: election,
            commitmentSet: preparation.commitmentSet
        )
        let playerCommit = playerCommits[0]
        let responseSet = try makeResponseSet(
            playerCommit: playerCommit,
            byteSeed: 1
        )
        let encoded = Codec.encodeAuthorizationResponseSet(responseSet)

        #expect(encoded.count == 6_011)
        #expect(encoded.count == Alpha.authorizationResponseSetCanonicalByteCount)
        #expect(try Codec.decodeAuthorizationResponseSet(from: encoded) == responseSet)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(responseSet.digest)
                == "d6c9888b23c2ee72d46e48ecd43a2cc4215c373a9a4183db914e6042cf53dbd7"
        )

        let reservation = try Alpha.AggregateReservation(
            aggregateKind: .authorizationResponseSet,
            aggregateDigest: responseSet.digest,
            declaredCanonicalByteCount: encoded.count
        )
        #expect(reservation.fragmentCount == 2)
        #expect(reservation.expectedBodyByteCount(at: 0) == 3_799)
        #expect(reservation.expectedBodyByteCount(at: 1) == 2_212)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                try Codec.encodeAggregateReservation(reservation)
            ) == "03d6c9888b23c2ee72d46e48ecd43a2cc4215c373a9a4183db914e6042cf53dbd70000177b02"
        )

        #expect(throws: Alpha.ContractError.invalidAuthorizationResponseCount(
            actual: 22
        )) {
            _ = try Alpha.AuthorizationResponseSet(
                roundIdentifier: playerCommit.roundIdentifier,
                contributor: playerCommit.contributor,
                playerCommitDigest: playerCommit.digest,
                responses: Array(responseSet.responses.dropLast())
            )
        }
        #expect(throws: Alpha.ContractError.invalidAuthorizationResponseCount(
            actual: 24
        )) {
            _ = try Alpha.AuthorizationResponseSet(
                roundIdentifier: playerCommit.roundIdentifier,
                contributor: playerCommit.contributor,
                playerCommitDigest: playerCommit.digest,
                responses: responseSet.responses + [
                    try .init(
                        slot: 0,
                        blindSignature: blindSignature(byte: 0xA5)
                    )
                ]
            )
        }
        var descending = responseSet.responses
        descending.swapAt(0, 1)
        #expect(throws: Alpha.ContractError.invalidAuthorizationResponseSlot(
            expected: 0,
            actual: 1
        )) {
            _ = try Alpha.AuthorizationResponseSet(
                roundIdentifier: playerCommit.roundIdentifier,
                contributor: playerCommit.contributor,
                playerCommitDigest: playerCommit.digest,
                responses: descending
            )
        }
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Codec.decodeAuthorizationResponseSet(from: encoded + [0])
        }
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.truncatedInput(
            expectedByteCount: 256,
            remainingByteCount: 255
        )) {
            _ = try Codec.decodeAuthorizationResponseSet(
                from: Array(encoded.dropLast())
            )
        }
        var invalidContributor = encoded
        invalidContributor.replaceSubrange(
            32 ..< 64,
            with: [UInt8](repeating: 0, count: 32)
        )
        #expect(throws: Alpha.ContractError.invalidControlIdentity) {
            _ = try Codec.decodeAuthorizationResponseSet(
                from: invalidContributor
            )
        }
        #expect(throws: Alpha.ContractError.invalidAggregateByteCount(
            actual: encoded.count - 1
        )) {
            _ = try Alpha.AggregateReservation(
                aggregateKind: .authorizationResponseSet,
                aggregateDigest: responseSet.digest,
                declaredCanonicalByteCount: encoded.count - 1
            )
        }
    }

    @Test("Construct response documents only after complete issuance")
    func requireCompleteAuthorizationIssuance() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let preparation = try makePreparation(election: election)
        let playerCommits = try makePlayerCommits(
            election: election,
            commitmentSet: preparation.commitmentSet
        )
        var ledger = OpalV0.AuthorizationIssuanceLedger(
            roster: election.result.roster
        )
        #expect(throws: OpalV0.AuthorizationIssuanceLedger.IssuedResponseError
            .issuanceIncomplete) {
            _ = try Alpha.AuthorizationResponseSet(
                playerCommit: playerCommits[0],
                issuingFrom: ledger
            )
        }

        for playerCommit in playerCommits {
            for request in playerCommit.authorizationRequests {
                _ = ledger.apply(
                    input: .request(
                        contributor: playerCommit.contributor,
                        slot: request.slot,
                        blindedMessage: request.blindedMessage
                    )
                )
            }
        }
        #expect(ledger.phase == .evaluating)
        for (contributorIndex, playerCommit) in playerCommits.enumerated() {
            for request in playerCommit.authorizationRequests {
                let key = OpalV0.AuthorizationIssuanceLedger.RequestKey(
                    contributor: playerCommit.contributor,
                    slot: request.slot
                )
                _ = ledger.apply(
                    input: .evaluated(
                        .init(
                            key: key,
                            blindSignature: try blindSignature(
                                byte: UInt8(contributorIndex + request.slot + 1)
                            )
                        )
                    )
                )
            }
        }
        #expect(ledger.phase == .issued)
        let issuedSet = try Alpha.AuthorizationResponseSet(
            playerCommit: playerCommits[0],
            issuingFrom: ledger
        )
        #expect(issuedSet.contributor == playerCommits[0].contributor)
        #expect(issuedSet.playerCommitDigest == playerCommits[0].digest)
        #expect(issuedSet.responses.map(\.slot) == Array(0 ..< 23))

        var substitutedRequests = playerCommits[0].authorizationRequests
        substitutedRequests[0] = try .init(
            slot: 0,
            blindedMessage: .init(
                rawRepresentation: Data(
                    repeating: 0xEE,
                    count: OpalV0.authorizationMaterialByteCount
                )
            )
        )
        let substitutedCommit = try Alpha.PlayerCommit(
            roundIdentifier: playerCommits[0].roundIdentifier,
            contributor: playerCommits[0].contributor,
            groupedCommitment: playerCommits[0].groupedCommitment,
            authorizationRequests: substitutedRequests
        )
        #expect(
            throws: OpalV0.AuthorizationIssuanceLedger.IssuedResponseError
                .requestMismatch(slot: 0)
        ) {
            _ = try Alpha.AuthorizationResponseSet(
                playerCommit: substitutedCommit,
                issuingFrom: ledger
            )
        }
    }

    @Test("Fail closed while finalizing contributor-local blind responses")
    func rejectInvalidAuthorizationResponses() throws {
        let verificationKey = try MosaicMainnetAlphaFixtures
            .rsaVerificationKey()
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let contributor = election.result.roster.contributors[0]
        var requests: [OpalV0.AuthorizationRequest] = []
        var payloads: [OpalV0.AuthorizationRequestPayload] = []
        for slot in 0 ..< Alpha.componentCountPerContributor {
            let input = try OpalV0.AuthorizationTokenInput(
                profile: .opalMainnetAlpha,
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                keyIdentifier: [UInt8](verificationKey.keyIdentifier),
                nonce: MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(
                    40_000 + slot
                )
            )
            let request = try OpalV0.AuthorizationRequest(
                input: input,
                using: verificationKey
            )
            requests.append(request)
            payloads.append(
                try .init(slot: slot, blindedMessage: request.blindedMessage)
            )
        }
        let playerCommit = try Alpha.PlayerCommit(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            contributor: contributor,
            groupedCommitment: MosaicOpalV0WireContractValidator
                .makeGroupedCommitment(),
            authorizationRequests: payloads
        )
        let invalidSet = try makeResponseSet(
            playerCommit: playerCommit,
            byteSeed: 1
        )
        #expect(throws: Alpha.AuthorizationResponseSetValidation.ValidationError
            .responseFinalizationFailed(slot: 0)) {
            _ = try Alpha.AuthorizationResponseSetValidation(
                validating: invalidSet,
                playerCommit: playerCommit,
                requests: requests,
                blindSigningVerificationKey: verificationKey
            )
        }
        #expect(throws: Alpha.AuthorizationResponseSetValidation.ValidationError
            .requestCountMismatch(actual: 22)) {
            _ = try Alpha.AuthorizationResponseSetValidation(
                validating: invalidSet,
                playerCommit: playerCommit,
                requests: Array(requests.dropLast()),
                blindSigningVerificationKey: verificationKey
            )
        }
        var wrongDigest = playerCommit.digest
        wrongDigest[0] ^= 0x01
        let mismatchedSet = try Alpha.AuthorizationResponseSet(
            roundIdentifier: playerCommit.roundIdentifier,
            contributor: contributor,
            playerCommitDigest: wrongDigest,
            responses: invalidSet.responses
        )
        #expect(throws: Alpha.AuthorizationResponseSetValidation.ValidationError
            .responseSetMismatch) {
            _ = try Alpha.AuthorizationResponseSetValidation(
                validating: mismatchedSet,
                playerCommit: playerCommit,
                requests: requests,
                blindSigningVerificationKey: verificationKey
            )
        }
    }

    @Test(
        "Freeze the roster-complete pre-sign acknowledgement set",
        arguments: [7, 8, 9]
    )
    func freezePreSignAcknowledgementSet(candidateCount: Int) throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection(
            candidateCount: candidateCount
        )
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: election.result.roster.contributors,
                binding: manifest.binding,
                transcriptRoot: try Attempt.TranscriptRoot(
                    validating: MosaicMainnetAlphaFixtures.transcriptRoot
                ),
                profile: .opalMainnetAlpha
            )
            .sorted {
                $0.contributor.validatedBytes.lexicographicallyPrecedes(
                    $1.contributor.validatedBytes
                )
            }
        let submissions = try acknowledgements.map {
            try Alpha.PreSignAcknowledgementSubmission(
                contributor: $0.contributor,
                roundIdentifier: $0.roundIdentifier,
                transcriptRoot: $0.transcriptRoot,
                signature: $0.rawRepresentation
            )
        }
        let acknowledgementSet = try Alpha.PreSignAcknowledgementSet(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
            roster: election.result.roster,
            submissions: submissions
        )
        let encoded = Codec.encodePreSignAcknowledgementSet(acknowledgementSet)
        let contributorCount = candidateCount - 1

        #expect(
            encoded.count == Alpha.preSignAcknowledgementSetCanonicalByteCount(
                contributorCount: contributorCount
            )
        )
        #expect(encoded.count == 68 + 96 * contributorCount)
        #expect(
            try Codec.decodePreSignAcknowledgementSet(
                from: encoded,
                roster: election.result.roster
            ) == acknowledgementSet
        )
        let expectedDigests = [
            7: "649350ee0ee9d85580480554ec4efb5908693cd9d581fe1f5fc0a5cd03559e32",
            8: "c3e49fe62c1b40f9eb23d2a8bca61e3ffc3e9ee5c8a0b23ec4ee0c30474a6107",
            9: "e127d4b472a41e77a0a365c911cccbd500bb21c9f14b1a32df3e35bb5412e510",
        ]
        let expectedDigest = try #require(expectedDigests[candidateCount])
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                acknowledgementSet.digest
            ) == expectedDigest
        )
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: .preSignAcknowledgementSet,
            aggregateDigest: acknowledgementSet.digest,
            declaredCanonicalByteCount: encoded.count
        )
        #expect(reservation.fragmentCount == 1)
        #expect(reservation.expectedBodyByteCount(at: 0) == encoded.count)

        guard candidateCount == 7 else {
            return
        }
        #expect(throws: Alpha.ContractError.invalidPreSignAcknowledgementCount(
            expected: 6,
            actual: 5
        )) {
            _ = try Alpha.PreSignAcknowledgementSet(
                roundIdentifier: manifest.binding.roundIdentifier,
                transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
                roster: election.result.roster,
                submissions: Array(submissions.dropLast())
            )
        }
        #expect(throws: Alpha.ContractError.invalidPreSignAcknowledgementContributor) {
            _ = try Alpha.PreSignAcknowledgementSet(
                roundIdentifier: manifest.binding.roundIdentifier,
                transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
                roster: election.result.roster,
                submissions: Array(submissions.reversed())
            )
        }
        #expect(throws: Alpha.ContractError.aggregateTranscriptMismatch) {
            _ = try Alpha.PreSignAcknowledgementSet(
                roundIdentifier: manifest.binding.roundIdentifier,
                transcriptRoot: [UInt8](repeating: 0x73, count: 32),
                roster: election.result.roster,
                submissions: submissions
            )
        }
        let conductorAcknowledgement = try #require(
            MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                for: [election.result.roster.conductor],
                binding: manifest.binding,
                transcriptRoot: try .init(
                    validating: MosaicMainnetAlphaFixtures.transcriptRoot
                ),
                profile: .opalMainnetAlpha
            ).first
        )
        var conductorSubstitution = submissions
        conductorSubstitution[0] = try .init(
            contributor: conductorAcknowledgement.contributor,
            roundIdentifier: conductorAcknowledgement.roundIdentifier,
            transcriptRoot: conductorAcknowledgement.transcriptRoot,
            signature: conductorAcknowledgement.rawRepresentation
        )
        conductorSubstitution.sort {
            $0.acknowledgement.contributor.validatedBytes
                .lexicographicallyPrecedes(
                    $1.acknowledgement.contributor.validatedBytes
                )
        }
        #expect(throws: Alpha.ContractError.invalidPreSignAcknowledgementContributor) {
            _ = try Alpha.PreSignAcknowledgementSet(
                roundIdentifier: manifest.binding.roundIdentifier,
                transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
                roster: election.result.roster,
                submissions: conductorSubstitution
            )
        }
        var invalidSignatureBytes = encoded
        invalidSignatureBytes[100] ^= 0x01
        #expect(throws: Alpha.ContractError.invalidControlSignature) {
            _ = try Codec.decodePreSignAcknowledgementSet(
                from: invalidSignatureBytes,
                roster: election.result.roster
            )
        }
        var substitutedMembers = election.result.roster.members
        let replacedContributor = submissions[0].acknowledgement.contributor
        let replacement = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 10
        )
        let replacedIndex = try #require(
            substitutedMembers.firstIndex {
                $0.controlIdentity == replacedContributor
            }
        )
        substitutedMembers[replacedIndex] = .init(
            controlIdentity: replacement,
            role: .contributor
        )
        let substitutedRoster = try Attempt.Roster(members: substitutedMembers)
        #expect(throws: Alpha.ContractError.invalidPreSignAcknowledgementContributor) {
            _ = try Codec.decodePreSignAcknowledgementSet(
                from: encoded,
                roster: substitutedRoster
            )
        }
        #expect(throws: OpalFusion.Mosaic.CanonicalCodingError.trailingBytes(1)) {
            _ = try Codec.decodePreSignAcknowledgementSet(
                from: encoded + [0],
                roster: election.result.roster
            )
        }
    }

    @Test("Reject wrong publishers and phases before aggregate reassembly")
    func rejectAggregateReservationMisrouting() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let roster = election.result.roster
        let playerCommit = try Alpha.PlayerCommit(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            contributor: roster.contributors[0],
            groupedCommitment: MosaicOpalV0WireContractValidator
                .makeGroupedCommitment(),
            authorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests()
        )
        let responseSet = try makeResponseSet(
            playerCommit: playerCommit,
            byteSeed: 1
        )
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: .authorizationResponseSet,
            aggregateDigest: responseSet.digest,
            declaredCanonicalByteCount: responseSet.canonicalBytes.count
        )
        let payload = try Codec.encodeAggregateReservation(reservation)
        let eventIdentity = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 9
        ).validatedBytes
        let contributorScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(for: roster.contributors[0])
        )
        let contributorEnvelope = try MosaicMainnetAlphaFixtures
            .signControlEnvelope(
                scalarByte: contributorScalar,
                senderEventIdentity: eventIdentity,
                phase: .walletReservation,
                payloadType: .aggregateReservation,
                payload: payload,
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier
            )
        #expect(throws: Alpha.ContractError.aggregatePublisherMismatch) {
            _ = try contributorEnvelope.admit(
                against: .init(
                    roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                    phase: .walletReservation,
                    roster: roster,
                    authenticatedOuterEventIdentity: eventIdentity,
                    currentUnixSeconds: 1_800_000_000
                )
            )
        }

        let conductorScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(for: roster.conductor)
        )
        let wrongPhaseEnvelope = try MosaicMainnetAlphaFixtures
            .signControlEnvelope(
                scalarByte: conductorScalar,
                senderEventIdentity: eventIdentity,
                phase: .groupedCommitment,
                payloadType: .aggregateReservation,
                payload: payload,
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier
            )
        #expect(throws: Alpha.ContractError.invalidPayloadPhase) {
            _ = try wrongPhaseEnvelope.admit(
                against: .init(
                    roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                    phase: .groupedCommitment,
                    roster: roster,
                    authenticatedOuterEventIdentity: eventIdentity,
                    currentUnixSeconds: 1_800_000_000
                )
            )
        }
    }

    private func makePreparation(
        election: MosaicRoleElectionFixtures.Election
    ) throws -> MosaicUnsignedTransactionTranscriptFixtures.Prepared {
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        return try MosaicUnsignedTransactionTranscriptFixtures.prepare(
            roster: election.result.roster,
            manifest: manifest.binding,
            profile: .opalMainnetAlpha
        )
    }

    private func makePlayerCommits(
        election: MosaicRoleElectionFixtures.Election,
        commitmentSet: OpalV0.CommitmentSet
    ) throws -> [Alpha.PlayerCommit] {
        let contributors = election.result.roster.contributors.sorted {
            $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
        }
        return try contributors.enumerated().map { index, contributor in
            let lower = index * Alpha.componentCountPerContributor
            let upper = lower + Alpha.componentCountPerContributor
            return try Alpha.PlayerCommit(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                contributor: contributor,
                groupedCommitment: .init(
                    commitments: Array(
                        commitmentSet.commitments[lower ..< upper]
                    ),
                    excessFeeSatoshis: 0,
                    pedersenTotalNonce:
                        [UInt8](repeating: 0, count: 31) + [UInt8(index + 1)]
                ),
                authorizationRequests: MosaicMainnetAlphaFixtures
                    .makeAuthorizationRequests()
            )
        }
    }

    private func makeResponseSet(
        playerCommit: Alpha.PlayerCommit,
        byteSeed: UInt8
    ) throws -> Alpha.AuthorizationResponseSet {
        try .init(
            roundIdentifier: playerCommit.roundIdentifier,
            contributor: playerCommit.contributor,
            playerCommitDigest: playerCommit.digest,
            responses: try (0 ..< Alpha.componentCountPerContributor).map {
                slot in
                try .init(
                    slot: slot,
                    blindSignature: try blindSignature(
                        byte: byteSeed &+ UInt8(slot)
                    )
                )
            }
        )
    }

    private func blindSignature(
        byte: UInt8
    ) throws -> OpalCrypto.RSABSSA.BlindSignature {
        try .init(
            rawRepresentation: Data(
                repeating: byte,
                count: OpalV0.authorizationMaterialByteCount
            )
        )
    }
}
