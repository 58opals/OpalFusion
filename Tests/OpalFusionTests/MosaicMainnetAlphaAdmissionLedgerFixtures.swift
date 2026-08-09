// MosaicMainnetAlphaAdmissionLedgerFixtures.swift

import Foundation
import OpalCrypto
@testable import OpalFusion

enum MosaicMainnetAlphaAdmissionLedgerFixtures {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Ledger = Alpha.AdmissionLedger

    struct Harness {
        let election: MosaicRoleElectionFixtures.Election
        let manifest: Alpha.RoundManifest
        let proposalValidation: Alpha.ManifestProposalValidation
        let attemptIdentifier: Ledger.AttemptIdentifier
        let generationIdentifier: Ledger.GenerationIdentifier
        let localControlIdentity: Attempt.ControlIdentity
        var ledger: Ledger
    }

    struct AggregateRun {
        let reservation: Ledger.ControlDelivery
        let fragments: [Ledger.ControlDelivery]

        var nextSequence: UInt64 {
            reservation.envelope.sequence + UInt64(fragments.count) + 1
        }
    }

    static func makeHarness(
        candidateCount: Int = 7,
        localRole: OpalFusion.Mosaic.Role,
        localContributorIndex: Int = 0,
        verificationKey: OpalCrypto.RSABSSA.VerificationKey? = nil
    ) throws -> Harness {
        let election = try MosaicMainnetAlphaFixtures.makeElection(
            candidateCount: candidateCount
        )
        let verificationKey = try verificationKey
            ?? MosaicMainnetAlphaFixtures.rsaVerificationKey()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: verificationKey
        )
        let context = try MosaicMainnetAlphaFixtures.makeManifestProposalContext(
            election: election
        )
        let proposalValidation = try Alpha.ManifestProposalValidation(
            validating: manifest.core,
            against: context
        )
        let localControlIdentity: Attempt.ControlIdentity
        switch localRole {
        case .conductor:
            localControlIdentity = election.result.roster.conductor
        case .contributor:
            guard election.result.roster.contributors.indices.contains(
                localContributorIndex
            ) else {
                throw FixtureError.invalidContributorIndex(
                    localContributorIndex
                )
            }
            localControlIdentity = election.result.roster
                .contributors[localContributorIndex]
        }
        let attemptIdentifier = Ledger.AttemptIdentifier(
            validatedBytes: [UInt8](repeating: 0xA1, count: 32)
        )
        let generationIdentifier = Ledger.GenerationIdentifier(
            opaqueBytes: [UInt8](repeating: 0xA2, count: 32)
        )
        let ledger = try Ledger(
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            localControlIdentity: localControlIdentity,
            proposalValidation: proposalValidation
        )
        return .init(
            election: election,
            manifest: manifest,
            proposalValidation: proposalValidation,
            attemptIdentifier: attemptIdentifier,
            generationIdentifier: generationIdentifier,
            localControlIdentity: localControlIdentity,
            ledger: ledger
        )
    }

    static func makeValidatedAttempt(
        election: MosaicRoleElectionFixtures.Election
    ) -> Attempt {
        var attempt = Attempt(
            configuration: .init(profile: .opalMainnetAlpha)
        )
        _ = attempt.apply(
            input: .discoveryCompleted(
                candidateCount: election.controlRoster.candidateCount
            )
        )
        _ = attempt.apply(input: .candidateSetAgreementValidated)
        _ = attempt.apply(
            input: .controlRosterValidated(election.controlRoster)
        )
        _ = attempt.apply(
            input: .roleCommitmentsReceived(election.commitments)
        )
        _ = attempt.apply(input: .roleElectionValidated(election.validation))
        return attempt
    }

    static func aggregateRun(
        canonicalBytes: [UInt8],
        kind: Alpha.AggregateKind,
        sender: Attempt.ControlIdentity,
        phase: Attempt.Phase,
        sequence: UInt64,
        harness: Harness
    ) throws -> AggregateRun {
        let digest = Alpha.RoleSeedValidator.hash(
            domainSuffix: kind.digestDomainSuffix,
            fields: [canonicalBytes]
        )
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: kind,
            aggregateDigest: digest,
            declaredCanonicalByteCount: canonicalBytes.count
        )
        let reservationEnvelope = try signedEnvelope(
            sender: sender,
            phase: phase,
            payloadType: .aggregateReservation,
            payload: try Alpha.CanonicalWireCodec.encodeAggregateReservation(
                reservation
            ),
            sequence: sequence,
            roundIdentifier: harness.manifest.core.roundIdentifier
        )
        let reservationDelivery = controlDelivery(
            envelope: reservationEnvelope,
            harness: harness
        )
        let capacity = Alpha.maximumAggregateFragmentBodyByteCount
        let fragments = try (0 ..< reservation.fragmentCount).map { index in
            let lowerBound = index * capacity
            let upperBound = min(lowerBound + capacity, canonicalBytes.count)
            let fragment = try Alpha.AggregateFragment(
                reservationSequence: sequence,
                fragmentIndex: index,
                body: Array(canonicalBytes[lowerBound ..< upperBound]),
                reservation: reservation
            )
            let envelope = try signedEnvelope(
                sender: sender,
                phase: phase,
                payloadType: .aggregateFragment,
                payload: try Alpha.CanonicalWireCodec.encodeAggregateFragment(
                    fragment
                ),
                sequence: sequence + UInt64(index) + 1,
                roundIdentifier: harness.manifest.core.roundIdentifier
            )
            return controlDelivery(envelope: envelope, harness: harness)
        }
        return .init(
            reservation: reservationDelivery,
            fragments: fragments
        )
    }

    static func admit(
        _ run: AggregateRun,
        to ledger: inout Ledger
    ) -> [Ledger.Effect] {
        var effects = ledger.apply(input: .control(run.reservation))
        for fragment in run.fragments {
            effects.append(contentsOf: ledger.apply(input: .control(fragment)))
        }
        return effects
    }

    static func controlDelivery(
        envelope: Alpha.ControlEnvelope,
        harness: Harness,
        attemptIdentifier: Ledger.AttemptIdentifier? = nil,
        generationIdentifier: Ledger.GenerationIdentifier? = nil,
        authenticatedOuterEventIdentity: [UInt8]? = nil,
        currentUnixSeconds: UInt64 = 1_800_000_000
    ) -> Ledger.ControlDelivery {
        .init(
            attemptIdentifier: attemptIdentifier ?? harness.attemptIdentifier,
            generationIdentifier:
                generationIdentifier ?? harness.generationIdentifier,
            envelope: envelope,
            authenticatedOuterEventIdentity:
                authenticatedOuterEventIdentity ?? envelope.senderEventIdentity,
            currentUnixSeconds: currentUnixSeconds
        )
    }

    static func signedEnvelope(
        sender: Attempt.ControlIdentity,
        phase: Attempt.Phase,
        payloadType: Alpha.ControlPayloadType,
        payload: [UInt8],
        sequence: UInt64,
        roundIdentifier: [UInt8]
    ) throws -> Alpha.ControlEnvelope {
        let scalarByte = try requiredScalarByte(for: sender)
        let eventScalar: UInt8 = scalarByte == 9 ? 10 : 9
        return try MosaicMainnetAlphaFixtures.signControlEnvelope(
            scalarByte: scalarByte,
            senderEventIdentity: eventIdentity(scalarByte: eventScalar),
            phase: phase,
            payloadType: payloadType,
            payload: payload,
            sequence: sequence,
            roundIdentifier: roundIdentifier
        )
    }

    static func makePlayerCommits(
        harness: Harness,
        commitmentSet: OpalFusion.Mosaic.OpalV0.CommitmentSet
    ) throws -> [Alpha.PlayerCommit] {
        let slotCount = Alpha.componentCountPerContributor
        let commitmentGroups = try MosaicUnsignedTransactionTranscriptFixtures
            .makeMainnetCommitmentGroups(
                contributorCount: harness.election.result.roster.contributors.count
            )
        let contributors = harness.election.result.roster.contributors.sorted {
            $0.validatedBytes.lexicographicallyPrecedes($1.validatedBytes)
        }
        return try contributors.enumerated().map { contributorIndex, contributor in
            let lowerBound = contributorIndex * slotCount
            let upperBound = lowerBound + slotCount
            let commitmentGroup = commitmentGroups[contributorIndex]
            precondition(
                Array(commitmentSet.commitments[lowerBound ..< upperBound])
                    == commitmentGroup.commitments
            )
            let groupedCommitment = try OpalFusion.Mosaic.OpalV0
                .GroupedCommitmentPayload(
                    profile: .opalMainnetAlpha,
                    commitments: commitmentGroup.commitments,
                    excessFeeSatoshis: commitmentGroup.excessFeeSatoshis,
                    pedersenTotalNonce: commitmentGroup.pedersenTotalNonce
                )
            return try Alpha.PlayerCommit(
                roundIdentifier: harness.manifest.core.roundIdentifier,
                contributor: contributor,
                groupedCommitment: groupedCommitment,
                authorizationRequests:
                    MosaicMainnetAlphaFixtures.makeAuthorizationRequests()
            )
        }
    }

    static func makeAuthorizationResponseSet(
        playerCommit: Alpha.PlayerCommit,
        byteSeed: UInt8 = 1
    ) throws -> Alpha.AuthorizationResponseSet {
        let responses = try (0 ..< Alpha.componentCountPerContributor).map {
            slot in
            try OpalFusion.Mosaic.OpalV0.AuthorizationResponsePayload(
                slot: slot,
                blindSignature: .init(
                    rawRepresentation: Data(
                        repeating: byteSeed &+ UInt8(slot),
                        count: OpalFusion.Mosaic.OpalV0
                            .authorizationMaterialByteCount
                    )
                )
            )
        }
        return try .init(
            roundIdentifier: playerCommit.roundIdentifier,
            contributor: playerCommit.contributor,
            playerCommitDigest: playerCommit.digest,
            responses: responses
        )
    }

    static func eventIdentity(scalarByte: UInt8) -> [UInt8] {
        precondition(scalarByte != 0)
        let signingKey = try! OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
        return [UInt8](
            signingKey.bip340VerificationKey.rawRepresentation
        )
    }

    static func requiredScalarByte(
        for identity: Attempt.ControlIdentity
    ) throws -> UInt8 {
        guard let scalarByte = MosaicMainnetAlphaFixtures.scalarByte(
            for: identity
        ) else {
            throw FixtureError.unknownControlIdentity
        }
        return scalarByte
    }

    enum FixtureError: Error {
        case unknownControlIdentity
        case invalidContributorIndex(Int)
    }
}
