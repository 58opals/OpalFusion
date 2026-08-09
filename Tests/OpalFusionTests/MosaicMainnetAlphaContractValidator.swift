// MosaicMainnetAlphaContractValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha contracts")
struct MosaicMainnetAlphaContractValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Codec = Alpha.CanonicalWireCodec

    private struct UnavailableAnonymousAdmissionValidator:
        Alpha.AnonymousComponentAdmissionValidating
    {
        struct Rejection: Error {}

        func validateComponentAdmission(
            senderCommunicationPublicKey: [UInt8],
            payload: OpalFusion.Mosaic.OpalV0.AnonymousComponentPayload
        ) throws {
            throw Rejection()
        }
    }

    @Test("Freeze the additive profile without changing the default")
    func freezeProfile() {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let configuration = OpalFusion.Mosaic.Configuration(profile: profile)

        #expect(profile.rawValue == "Mosaic/0-opal-mainnet-alpha.2")
        #expect(profile.protocolVersion == .opalMainnetAlpha)
        #expect(profile.transportProfile == .nostrTorOpalMainnetAlpha)
        #expect(profile.rosterPolicy == .opalMainnetAlpha)
        #expect(
            profile.transactionProfileIdentifier
                == "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.2"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                profile.networkGenesisHash ?? []
            ) == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        )
        #expect(configuration.profile == profile)
        #expect(OpalFusion.Mosaic.Configuration().profile == .draft1)
        #expect(OpalFusion.Mosaic.Profile.opalV0.rawValue == "Mosaic/0-opal.1")
    }

    @Test("Derive and validate the frozen role hash documents")
    func deriveRoleHashDocuments() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()

        #expect(election.validation.roleSeed.count == 32)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                election.commitments[0].commitment
            ) == "0a659aa11484d98ebd1f55f9f00801368f704ab9eefd41f0a7c5b79b38ef5e3b"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                election.validation.roleSeed
            ) == "c63fbc68ac2cc58c99f162a01ab014f67dea9c11a6a5341fa08db552153825f9"
        )
        #expect(election.result.profile == .opalMainnetAlpha)
        #expect(election.result.roster.candidateCount == 7)

        var invalidCommitments = election.commitments
        invalidCommitments[0] = Attempt.RoleCommitment(
            candidate: invalidCommitments[0].candidate,
            controlRosterDigest: invalidCommitments[0].controlRosterDigest,
            commitment: [UInt8](repeating: 0, count: 32)
        )
        let invalidSet = try Attempt.RoleCommitmentSet(
            controlRoster: election.controlRoster,
            commitments: invalidCommitments
        )
        #expect(throws: Attempt.RoleSeedValidation.ValidationError.validatorRejected) {
            _ = try Attempt.RoleSeedValidation(
                profile: .opalMainnetAlpha,
                commitmentSet: invalidSet,
                reveals: election.reveals,
                using: Alpha.RoleSeedValidator()
            )
        }
    }

    @Test("Round-trip the complete signed manifest and reject cross-profile bytes")
    func roundTripManifest() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let encoded = Codec.encodeManifest(manifest)
        let decoded = try Codec.decodeManifest(
            from: encoded,
            expectedContext: MosaicMainnetAlphaFixtures
                .makeManifestProposalContext(election: election)
        )
        #expect(decoded == manifest)
        #expect(
            encoded.count
                == Alpha.completeManifestCanonicalByteCount(candidateCount: 7)
        )
        #expect(
            manifest.core.blindSigningVerificationKey
                .subjectPublicKeyInfo.count
                == Alpha.blindSigningVerificationKeyByteCount
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                manifest.core.roundIdentifier
            ) == "f942471d6fda5924e493fc07163588e67053d0c0488c4dde748ec36b1dd0d468"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                manifest.binding.manifestDigest
            ) == "8741512c775f6c75346d5c59674b44d073f9009c2644c827286286675adb0cb6"
        )
        #expect(manifest.binding.roundIdentifier == manifest.core.roundIdentifier)
        #expect(manifest.binding.manifestDigest.count == 32)
        #expect(manifest.signatures.count == 7)

        var crossProfile = encoded
        let profileLength = Int(UInt32(bigEndianBytes: Array(crossProfile[0 ..< 4])))
        let profileRange = 4 ..< 4 + profileLength
        crossProfile.replaceSubrange(
            profileRange,
            with: Array("Mosaic/0-opal-mainnet-alpha.0".utf8)
        )
        #expect(throws: Alpha.ContractError.profileMismatch) {
            _ = try Codec.decodeManifest(
                from: crossProfile,
                expectedContext: MosaicMainnetAlphaFixtures
                    .makeManifestProposalContext(election: election)
            )
        }

        #expect(throws: Alpha.ContractError.invalidManifestSignatureCount(
            expected: 7,
            actual: 6
        )) {
            _ = try Alpha.RoundManifest(
                core: manifest.core,
                signatures: Array(manifest.signatures.dropLast())
            )
        }

        let wrongCandidateContext = try Alpha.ManifestProposalContext(
            roleElection: election.result,
            candidateSetDigest: [UInt8](repeating: 0x40, count: 32),
            opaquePoolIdentifier: [UInt8](repeating: 0x42, count: 32)
        )
        #expect(throws: Alpha.ContractError.candidateSetDigestMismatch) {
            _ = try Codec.decodeManifest(
                from: encoded,
                expectedContext: wrongCandidateContext
            )
        }

        let wrongPoolContext = try Alpha.ManifestProposalContext(
            roleElection: election.result,
            candidateSetDigest: [UInt8](repeating: 0x41, count: 32),
            opaquePoolIdentifier: [UInt8](repeating: 0x43, count: 32)
        )
        #expect(throws: Alpha.ContractError.poolIdentifierMismatch) {
            _ = try Codec.decodeManifest(
                from: encoded,
                expectedContext: wrongPoolContext
            )
        }
    }

    @Test("Round-trip PlayerCommit and enforce exact slot correspondence")
    func roundTripPlayerCommit() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let playerCommit = try Alpha.PlayerCommit(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            contributor: election.result.roster.contributors[0],
            groupedCommitment: MosaicOpalV0WireContractValidator
                .makeGroupedCommitment(),
            authorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests()
        )
        let decoded = try Codec.decodePlayerCommit(
            from: Codec.encodePlayerCommit(playerCommit)
        )
        #expect(decoded == playerCommit)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                playerCommit.digest
            ) == "ca9602bb99cacf7617c45ec788eab7cea20be588df22b83be0342f3ea3bff891"
        )

        var requests = try MosaicMainnetAlphaFixtures.makeAuthorizationRequests()
        requests.swapAt(0, 1)
        #expect(throws: Alpha.ContractError.invalidAuthorizationRequestSlot(
            expected: 0,
            actual: 1
        )) {
            _ = try Alpha.PlayerCommit(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                contributor: election.result.roster.contributors[0],
                groupedCommitment: MosaicOpalV0WireContractValidator
                    .makeGroupedCommitment(),
                authorizationRequests: requests
            )
        }
    }

    @Test("Reserve and reassemble one exact strict sequence run")
    func reserveAggregateSequence() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let componentSet = try MosaicUnsignedTransactionTranscriptFixtures
            .makeBalancedComponentSet(
                contributorCount: election.result.roster.contributors.count,
                profile: .opalMainnetAlpha
            )
        let bytes = OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
            .encodeComponentSet(componentSet)
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: .componentSet,
            aggregateDigest: componentSet.digest,
            declaredCanonicalByteCount: bytes.count
        )
        #expect(reservation.fragmentCount == 2)
        let encodedReservation = try Codec.encodeAggregateReservation(reservation)
        #expect(
            try Codec.decodeAggregateReservation(from: encodedReservation)
                == reservation
        )

        let fragments = try (0 ..< reservation.fragmentCount).map { index in
            let capacity = Alpha.maximumAggregateFragmentBodyByteCount
            let lower = index * capacity
            let upper = min(lower + capacity, bytes.count)
            return try Alpha.AggregateFragment(
                reservationSequence: 10,
                fragmentIndex: index,
                body: Array(bytes[lower ..< upper]),
                reservation: reservation
            )
        }
        var reassembler = try Alpha.AggregateReassembler(
            reservationSequence: 10,
            reservation: reservation,
            decodingContext: .profileOnly
        )
        #expect(reassembler.receive(fragments[0], at: 11) == .accepted(
            received: 1,
            expected: 2
        ))
        #expect(reassembler.receive(fragments[0], at: 11) == .exactDuplicate(
            fragmentIndex: 0
        ))
        #expect(
            reassembler.receive(fragments[1], at: 12)
                == .completed(.componentSet(componentSet))
        )
        #expect(reassembler.receive(fragments[1], at: 12) == .inputAfterTermination)

        #expect(throws: Alpha.ContractError.invalidAggregateByteCount(actual: 1_000)) {
            _ = try Alpha.AggregateReservation(
                aggregateKind: .componentSet,
                aggregateDigest: [UInt8](repeating: 0, count: 32),
                declaredCanonicalByteCount: 1_000
            )
        }

        let malformedBytes = [UInt8](repeating: 0, count: bytes.count)
        let malformedReservation = try Alpha.AggregateReservation(
            aggregateKind: .componentSet,
            aggregateDigest: Alpha.RoleSeedValidator.hash(
                domainSuffix: "component-set",
                fields: [malformedBytes]
            ),
            declaredCanonicalByteCount: malformedBytes.count
        )
        let malformedFragments = try (0 ..< malformedReservation.fragmentCount)
            .map { index in
                let capacity = Alpha.maximumAggregateFragmentBodyByteCount
                let lower = index * capacity
                let upper = min(lower + capacity, malformedBytes.count)
                return try Alpha.AggregateFragment(
                    reservationSequence: 20,
                    fragmentIndex: index,
                    body: Array(malformedBytes[lower ..< upper]),
                    reservation: malformedReservation
                )
            }
        var malformedReassembler = try Alpha.AggregateReassembler(
            reservationSequence: 20,
            reservation: malformedReservation,
            decodingContext: .profileOnly
        )
        #expect(
            malformedReassembler.receive(malformedFragments[0], at: 21)
                == .accepted(received: 1, expected: 2)
        )
        #expect(
            malformedReassembler.receive(malformedFragments[1], at: 22)
                == .terminated(.invalidCanonicalAggregate(.componentSet))
        )
    }

    @Test("Authenticate and round-trip a control envelope")
    func roundTripControlEnvelope() throws {
        let eventKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([9])
        ).bip340VerificationKey
        let envelope = try MosaicMainnetAlphaFixtures.signControlEnvelope(
            scalarByte: 1,
            senderEventIdentity: [UInt8](eventKey.rawRepresentation),
            phase: .manifestAgreement,
            payloadType: .aggregateReservation,
            payload: [0x01, 0x02, 0x03]
        )
        let decoded = try Codec.decodeControlEnvelope(
            from: Codec.encodeControlEnvelope(envelope)
        )
        #expect(decoded == envelope)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                envelope.messageDigest
            ) == "36c11ac8a578359bcffddc70721bf7a81d94b3c0019a2e96b6959759d3526870"
        )
        let encodedEnvelopeDigest = MosaicOpalV0WireContractValidator
            .hexadecimal(
                [UInt8](OpalCrypto.Hashing.sha256(
                    Data(try Codec.encodeControlEnvelope(envelope))
                ))
            )
        #expect(
            encodedEnvelopeDigest
                == "d0a61533355a6b345f7bcf10df6dff0e302c2a889e5d4176b563147dd3922eb7"
        )
        #expect(throws: Alpha.ContractError.outerEventIdentityMismatch) {
            try envelope.validateOuterEventIdentity(
                [UInt8](repeating: 0, count: 32)
            )
        }
    }

    @Test("Bind anonymous payloads to one communication event identity and phase")
    func roundTripAnonymousEnvelope() throws {
        let communicationKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 1_200).compressed
        let recipient = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 9
        ).validatedBytes
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            phase: .bchSigning,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: recipient,
            sequence: 0,
            payloadType: .bchSignatureSubmission,
            expiryUnixSeconds: 1_800_000_060,
            payload: [0xAA]
        )
        let decoded = try Codec.decodeAnonymousEnvelope(
            from: Codec.encodeAnonymousEnvelope(envelope)
        )
        #expect(decoded == envelope)
        let encodedEnvelopeDigest = MosaicOpalV0WireContractValidator
            .hexadecimal(
                [UInt8](OpalCrypto.Hashing.sha256(
                    Data(try Codec.encodeAnonymousEnvelope(envelope))
                ))
            )
        #expect(
            encodedEnvelopeDigest
                == "2ad4e9e4ea5ac857d4f4414ffd333c6308ef9191164c6fe8150f2dc5221dd88a"
        )
        try envelope.validateOuterEventIdentity(
            Array(communicationKey.dropFirst())
        )
        #expect(throws: Alpha.ContractError.invalidPayloadPhase) {
            _ = try Alpha.AnonymousEnvelope(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                phase: .anonymousComponentSubmission,
                senderCommunicationPublicKey: communicationKey,
                recipientEventIdentity: recipient,
                sequence: 0,
                payloadType: .bchSignatureSubmission,
                expiryUnixSeconds: 1_800_000_060,
                payload: [0xAA]
            )
        }
    }

    @Test("Canonicalize a complete input-indexed BCH signature set")
    func roundTripBCHSignatureSet() throws {
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([11])
        )
        let signature = try signingKey.signSchnorr(
            digest: .init(rawRepresentation: Data(repeating: 0x51, count: 32))
        )
        let entry = try Alpha.BCHSignatureEntry(
            inputIndex: 0,
            signature: [UInt8](signature.rawRepresentation),
            publicKey: [UInt8](signingKey.publicKey.compressedRepresentation)
        )
        let submission = try Alpha.BCHSignatureSubmission(
            transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
            entry: entry
        )
        let signatureSet = try Alpha.BCHSignatureSet(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
            submissions: [submission],
            expectedInputCount: 1
        )
        let decoded = try Codec.decodeBCHSignatureSet(
            from: Codec.encodeBCHSignatureSet(signatureSet),
            expectedInputCount: 1
        )
        #expect(decoded == signatureSet)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                signatureSet.digest
            ) == "1688cfcaf4fdf398cc222f21e01bf3833f9bcc724d26ca7ec02f89e633b7e194"
        )
        #expect(signatureSet.entries.map(\.inputIndex) == [0])
        #expect(throws: Alpha.ContractError.invalidSignatureSetCount(
            expected: 2,
            actual: 1
        )) {
            _ = try Alpha.BCHSignatureSet(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
                submissions: [submission],
                expectedInputCount: 2
            )
        }

        let secondEntry = try Alpha.BCHSignatureEntry(
            inputIndex: 1,
            signature: entry.signature,
            publicKey: entry.publicKey
        )
        var descendingEncoder = OpalFusion.Mosaic.CanonicalEncoder()
        try descendingEncoder.writeFixedBytes(
            MosaicMainnetAlphaFixtures.roundIdentifier,
            byteCount: 32
        )
        try descendingEncoder.writeFixedBytes(
            MosaicMainnetAlphaFixtures.transcriptRoot,
            byteCount: 32
        )
        try descendingEncoder.writeVector([secondEntry, entry]) {
            encoder, value in
            encoder.writeUInt32(value.inputIndex)
            try encoder.writeFixedBytes(value.signature, byteCount: 64)
            try encoder.writeFixedBytes(value.publicKey, byteCount: 33)
        }
        #expect(throws: Alpha.ContractError.nonCanonicalSignatureOrder) {
            _ = try Codec.decodeBCHSignatureSet(
                from: descendingEncoder.encodedBytes,
                expectedInputCount: 2
            )
        }
    }

    @Test("Seal control payloads to their authenticated round, phase, and publisher")
    func admitControlPayloads() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let roster = election.result.roster
        let contributor = roster.contributors[0]
        let contributorScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(for: contributor)
        )
        let conductorScalar = try #require(
            MosaicMainnetAlphaFixtures.scalarByte(for: roster.conductor)
        )
        let eventIdentity = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 9
        ).validatedBytes
        let playerCommit = try Alpha.PlayerCommit(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            contributor: contributor,
            groupedCommitment: MosaicOpalV0WireContractValidator
                .makeGroupedCommitment(),
            authorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests()
        )
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: .playerCommit,
            aggregateDigest: playerCommit.digest,
            declaredCanonicalByteCount: playerCommit.canonicalBytes.count
        )
        let reservationPayload = try Codec.encodeAggregateReservation(
            reservation
        )
        let envelope = try MosaicMainnetAlphaFixtures.signControlEnvelope(
            scalarByte: contributorScalar,
            senderEventIdentity: eventIdentity,
            phase: .walletReservation,
            payloadType: .aggregateReservation,
            payload: reservationPayload
        )
        let context = try Alpha.ControlAdmissionContext(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            phase: .walletReservation,
            roster: roster,
            authenticatedOuterEventIdentity: eventIdentity,
            currentUnixSeconds: 1_800_000_000
        )
        #expect(
            try envelope.admit(against: context)
                == .aggregateReservation(
                    .init(
                        sender: contributor,
                        phase: .walletReservation,
                        reservationSequence: 0,
                        reservation: reservation
                    )
                )
        )

        let conductorEnvelope = try MosaicMainnetAlphaFixtures
            .signControlEnvelope(
                scalarByte: conductorScalar,
                senderEventIdentity: eventIdentity,
                phase: .walletReservation,
                payloadType: .aggregateReservation,
                payload: reservationPayload
            )
        #expect(throws: Alpha.ContractError.aggregatePublisherMismatch) {
            _ = try conductorEnvelope.admit(against: context)
        }
        #expect(throws: Alpha.ContractError.outerEventIdentityMismatch) {
            _ = try envelope.admit(
                against: .init(
                    roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                    phase: .walletReservation,
                    roster: roster,
                    authenticatedOuterEventIdentity:
                        [UInt8](repeating: 0, count: 32),
                    currentUnixSeconds: 1_800_000_000
                )
            )
        }
        #expect(throws: Alpha.ContractError.expiredEnvelope(
            expiryUnixSeconds: 1_800_000_060,
            currentUnixSeconds: 1_800_000_061
        )) {
            _ = try envelope.admit(
                against: .init(
                    roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                    phase: .walletReservation,
                    roster: roster,
                    authenticatedOuterEventIdentity: eventIdentity,
                    currentUnixSeconds: 1_800_000_061
                )
            )
        }

        let wrongPhaseEnvelope = try MosaicMainnetAlphaFixtures
            .signControlEnvelope(
                scalarByte: contributorScalar,
                senderEventIdentity: eventIdentity,
                phase: .groupedCommitment,
                payloadType: .aggregateReservation,
                payload: reservationPayload
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

        let publicationContext = try Alpha.AggregatePublicationContext(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            phase: .walletReservation,
            sender: contributor,
            roster: roster
        )
        #expect(
            try Alpha.ValidatedAggregatePublication(
                document: .playerCommit(playerCommit),
                context: publicationContext
            ).document == .playerCommit(playerCommit)
        )
        let foreignRoundCommit = try Alpha.PlayerCommit(
            roundIdentifier: [UInt8](repeating: 0x70, count: 32),
            contributor: contributor,
            groupedCommitment: playerCommit.groupedCommitment,
            authorizationRequests: playerCommit.authorizationRequests
        )
        #expect(throws: Alpha.ContractError.aggregateRoundMismatch) {
            _ = try Alpha.ValidatedAggregatePublication(
                document: .playerCommit(foreignRoundCommit),
                context: publicationContext
            )
        }
        let forgedContributorCommit = try Alpha.PlayerCommit(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            contributor: roster.contributors[1],
            groupedCommitment: playerCommit.groupedCommitment,
            authorizationRequests: playerCommit.authorizationRequests
        )
        #expect(throws: Alpha.ContractError.aggregatePublisherMismatch) {
            _ = try Alpha.ValidatedAggregatePublication(
                document: .playerCommit(forgedContributorCommit),
                context: publicationContext
            )
        }

        let transcriptRoot = try Attempt.TranscriptRoot(
            validating: MosaicMainnetAlphaFixtures.transcriptRoot
        )
        let binding = try Attempt.ManifestBinding(
            validatedRoundIdentifier:
                MosaicMainnetAlphaFixtures.roundIdentifier,
            validatedManifestDigest: [UInt8](repeating: 0x73, count: 32)
        )
        let acknowledgement = try #require(
            MosaicManifestSignatureFixtures.transcriptAcknowledgements(
                for: [contributor],
                binding: binding,
                transcriptRoot: transcriptRoot,
                profile: .opalMainnetAlpha
            ).first
        )
        let acknowledgementPayload = try Codec
            .encodePreSignAcknowledgementSubmission(
                roundIdentifier: acknowledgement.roundIdentifier,
                transcriptRoot: acknowledgement.transcriptRoot,
                signature: acknowledgement.rawRepresentation
            )
        let acknowledgementEnvelope = try MosaicMainnetAlphaFixtures
            .signControlEnvelope(
                scalarByte: contributorScalar,
                senderEventIdentity: eventIdentity,
                phase: .transcriptAgreement,
                payloadType: .preSignAcknowledgement,
                payload: acknowledgementPayload
            )
        let admittedAcknowledgement = try acknowledgementEnvelope.admit(
            against: .init(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                phase: .transcriptAgreement,
                roster: roster,
                authenticatedOuterEventIdentity: eventIdentity,
                currentUnixSeconds: 1_800_000_000
            )
        )
        if case let .preSignAcknowledgement(submission) = admittedAcknowledgement {
            #expect(submission.acknowledgement == acknowledgement)
        } else {
            Issue.record("Expected a sealed pre-sign acknowledgement")
        }
    }

    @Test("Keep anonymous BCH-signature admission fail closed")
    func rejectUnfrozenAnonymousSignatureAdmission() throws {
        let communicationKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 1_201).compressed
        let outerEventIdentity = Array(communicationKey.dropFirst())
        let recipientEventIdentity = MosaicManifestSignatureFixtures
            .controlIdentity(scalarByte: 9).validatedBytes
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            phase: .bchSigning,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: recipientEventIdentity,
            sequence: 0,
            payloadType: .bchSignatureSubmission,
            expiryUnixSeconds: 1_800_000_060,
            payload: [0xAA]
        )
        #expect(throws: Alpha.ContractError.unsupportedAnonymousPayloadType(
            .bchSignatureSubmission
        )) {
            _ = try Alpha.AnonymousComponentAdmissionValidation(
                envelope: envelope,
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                authenticatedOuterEventIdentity: outerEventIdentity,
                expectedRecipientEventIdentity: recipientEventIdentity,
                currentUnixSeconds: 1_800_000_000,
                blindSigningVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey(),
                using: UnavailableAnonymousAdmissionValidator()
            )
        }
        #expect(throws: Alpha.ContractError.communicationEventIdentityMismatch) {
            _ = try Alpha.AnonymousComponentAdmissionValidation(
                envelope: envelope,
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                authenticatedOuterEventIdentity:
                    [UInt8](repeating: 0, count: 32),
                expectedRecipientEventIdentity: recipientEventIdentity,
                currentUnixSeconds: 1_800_000_000,
                blindSigningVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey(),
                using: UnavailableAnonymousAdmissionValidator()
            )
        }
        #expect(throws: Alpha.ContractError.recipientEventIdentityMismatch) {
            _ = try Alpha.AnonymousComponentAdmissionValidation(
                envelope: envelope,
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                authenticatedOuterEventIdentity: outerEventIdentity,
                expectedRecipientEventIdentity:
                    [UInt8](repeating: 0, count: 32),
                currentUnixSeconds: 1_800_000_000,
                blindSigningVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey(),
                using: UnavailableAnonymousAdmissionValidator()
            )
        }
        #expect(throws: Alpha.ContractError.expiredEnvelope(
            expiryUnixSeconds: 1_800_000_060,
            currentUnixSeconds: 1_800_000_061
        )) {
            _ = try Alpha.AnonymousComponentAdmissionValidation(
                envelope: envelope,
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                authenticatedOuterEventIdentity: outerEventIdentity,
                expectedRecipientEventIdentity: recipientEventIdentity,
                currentUnixSeconds: 1_800_000_061,
                blindSigningVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey(),
                using: UnavailableAnonymousAdmissionValidator()
            )
        }
    }

    @Test("Freeze mainnet-alpha authorization and transcript bindings")
    func freezeAuthorizationAndTranscriptBindings() throws {
        let tokenInput = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
            profile: .opalMainnetAlpha,
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            keyIdentifier: [UInt8](repeating: 0x81, count: 32),
            nonce: [UInt8](repeating: 0x82, count: 32)
        )
        let expectedTokenInput = "0000003b4d6f736169632f302d6f70616c2d6d61696e6e65742d616c7068612e322f636f6d706f6e656e742d617574686f72697a6174696f6e2f696e70757400000020000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f000000207171717171717171717171717171717171717171717171717171717171717171000000208181818181818181818181818181818181818181818181818181818181818181000000208282828282828282828282828282828282828282828282828282828282828282"
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                tokenInput.canonicalBytes
            ) == expectedTokenInput
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                tokenInput.spentIdentifier
            ) == "6e624d947fc4631022132bf79f6d4b4fe80173e89de11a447428aab46ba2debf"
        )
        let opalV0Input = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            keyIdentifier: [UInt8](repeating: 0x81, count: 32),
            nonce: [UInt8](repeating: 0x82, count: 32)
        )
        #expect(tokenInput.spentIdentifier != opalV0Input.spentIdentifier)

        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: election.result.roster,
                manifest: manifest.binding,
                profile: .opalMainnetAlpha
            )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                preparation.commitmentSet.digest
            ) == "fc59d1190cebd7aef3b08c60666244c4b5dd871ffe7a0af26575876bd0fd2f85"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                preparation.componentSet.digest
            ) == "bc85640e5c56b8f5013264c8cf77af9bec6186e6d9582041cb935370a6ea59dc"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                preparation.transcript.transcriptRoot.validatedBytes
            ) == "07f68d2131f81fa60def9f6046e070bd258e1c1b118f9193e25737424a51203e"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                [UInt8](OpalCrypto.Hashing.sha256(
                    Data(preparation.transcript.unsignedTransactionBytes)
                ))
            ) == "6519f7d0bc1fc9c0717a79f5f76afb3d2235aa7cfe52b2f4d4ab0bde567bf512"
        )
    }

    @Test("Assemble and bind one exact fully signed mainnet-alpha transaction")
    func assembleCompleteTransaction() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let preparation = try MosaicUnsignedTransactionTranscriptFixtures
            .prepare(
                roster: election.result.roster,
                manifest: manifest.binding,
                profile: .opalMainnetAlpha
            )
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([11])
        )
        let publicKey = [UInt8](signingKey.publicKey.compressedRepresentation)
        let lockingScript = [UInt8(0x76), 0xa9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xac]
        let spentInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes:
                MosaicUnsignedTransactionTranscriptFixtures.indexedDigest(1_000),
            outpointIndex: 3,
            amountSatoshis: 10_185,
            lockingScriptBytes: lockingScript,
            publicKey: publicKey
        )
        let signatureHash = try preparation.transcript.transaction.signatureHash(
            forInputAt: 0,
            lockingScript: lockingScript,
            amountSatoshis: spentInput.amountSatoshis,
            sighashType: 0x41
        )
        let signature = try signingKey.signSchnorr(
            digest: .init(rawRepresentation: Data(signatureHash))
        )
        let entry = try Alpha.BCHSignatureEntry(
            inputIndex: 0,
            signature: [UInt8](signature.rawRepresentation),
            publicKey: publicKey
        )
        let signatureSet = try Alpha.BCHSignatureSet(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot:
                preparation.transcript.transcriptRoot.validatedBytes,
            submissions: [
                try .init(
                    transcriptRoot:
                        preparation.transcript.transcriptRoot.validatedBytes,
                    entry: entry
                )
            ],
            expectedInputCount: 1
        )
        let complete = try Alpha.CompleteTransactionAssembler.assemble(
            transcript: preparation.transcript,
            signatureSet: signatureSet,
            spentInputs: [spentInput]
        )
        let parsed = try OpalFusion.Execution.BCHTransaction.parse(
            complete.transactionBytes
        )
        #expect(parsed.inputs[0].unlockingScript.count == 100)
        #expect(parsed.inputs[0].unlockingScript[0] == 0x41)
        #expect(parsed.inputs[0].unlockingScript[65] == 0x41)
        #expect(parsed.inputs[0].unlockingScript[66] == 0x21)

        let payload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot:
                preparation.transcript.transcriptRoot.validatedBytes,
            completeTransaction: complete
        )
        #expect(
            try Codec.decodeCompleteTransactionPayload(
                from: Codec.encodeCompleteTransactionPayload(payload)
            ) == payload
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                payload.digest
            ) == "3b88af516ef8cdfca134b6148aa7019507ff312d4d68f9b063af05a24c338f5f"
        )
        let publicationContext = try Alpha.AggregatePublicationContext(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot:
                preparation.transcript.transcriptRoot.validatedBytes,
            phase: .bchSigning,
            sender: election.result.roster.conductor,
            roster: election.result.roster,
            expectedTranscript: preparation.transcript
        )
        #expect(
            try Alpha.ValidatedAggregatePublication(
                document: .completeTransaction(payload),
                context: publicationContext
            ).document == .completeTransaction(payload)
        )

        var substitutedTransaction = parsed
        substitutedTransaction.outputs[0].amountSatoshis -= 1
        let substitutedComplete = try OpalFusion.Host
            .MosaicCompleteTransaction(
                transactionBytes: substitutedTransaction.serialize()
            )
        let substitutedPayload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot:
                preparation.transcript.transcriptRoot.validatedBytes,
            completeTransaction: substitutedComplete
        )
        #expect(throws: Alpha.ContractError.transactionMismatch) {
            _ = try Alpha.ValidatedAggregatePublication(
                document: .completeTransaction(substitutedPayload),
                context: publicationContext
            )
        }
        #expect(throws: Alpha.ContractError.transactionMismatch) {
            _ = try Alpha.AggregateDecodingContext.completeTransaction(
                expectedTranscript: preparation.transcript
            ).decode(
                substitutedPayload.canonicalBytes,
                kind: .completeTransaction
            )
        }

        let wrongOutpoint = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: [UInt8](repeating: 0, count: 32),
            outpointIndex: spentInput.outpointIndex,
            amountSatoshis: spentInput.amountSatoshis,
            lockingScriptBytes: lockingScript,
            publicKey: publicKey
        )
        #expect(throws: Alpha.ContractError.invalidSpentInput(index: 0)) {
            _ = try Alpha.CompleteTransactionAssembler.assemble(
                transcript: preparation.transcript,
                signatureSet: signatureSet,
                spentInputs: [wrongOutpoint]
            )
        }

        let wrongAmountInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes:
                spentInput.outpointTransactionHashBytes,
            outpointIndex: spentInput.outpointIndex,
            amountSatoshis: spentInput.amountSatoshis + 1,
            lockingScriptBytes: lockingScript,
            publicKey: publicKey
        )
        let wrongAmountHash = try preparation.transcript.transaction.signatureHash(
            forInputAt: 0,
            lockingScript: lockingScript,
            amountSatoshis: wrongAmountInput.amountSatoshis,
            sighashType: 0x41
        )
        let wrongAmountSignature = try signingKey.signSchnorr(
            digest: .init(rawRepresentation: Data(wrongAmountHash))
        )
        let wrongAmountEntry = try Alpha.BCHSignatureEntry(
            inputIndex: 0,
            signature: [UInt8](wrongAmountSignature.rawRepresentation),
            publicKey: publicKey
        )
        let wrongAmountSet = try Alpha.BCHSignatureSet(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot:
                preparation.transcript.transcriptRoot.validatedBytes,
            submissions: [
                try .init(
                    transcriptRoot:
                        preparation.transcript.transcriptRoot.validatedBytes,
                    entry: wrongAmountEntry
                )
            ],
            expectedInputCount: 1
        )
        #expect(throws: Alpha.ContractError.invalidSpentInput(index: 0)) {
            _ = try Alpha.CompleteTransactionAssembler.assemble(
                transcript: preparation.transcript,
                signatureSet: wrongAmountSet,
                spentInputs: [wrongAmountInput]
            )
        }

        let wrongLockingScript = MosaicUnsignedTransactionTranscriptFixtures
            .p2pkhLockingScript(fill: 0x55)
        let wrongScriptInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes:
                spentInput.outpointTransactionHashBytes,
            outpointIndex: spentInput.outpointIndex,
            amountSatoshis: spentInput.amountSatoshis,
            lockingScriptBytes: wrongLockingScript,
            publicKey: publicKey
        )
        #expect(throws: Alpha.ContractError.invalidP2PKHLockingScript(index: 0)) {
            _ = try Alpha.CompleteTransactionAssembler.assemble(
                transcript: preparation.transcript,
                signatureSet: signatureSet,
                spentInputs: [wrongScriptInput]
            )
        }

        let wrongSignature = try signingKey.signSchnorr(
            digest: .init(rawRepresentation: Data(repeating: 0x99, count: 32))
        )
        let invalidEntry = try Alpha.BCHSignatureEntry(
            inputIndex: 0,
            signature: [UInt8](wrongSignature.rawRepresentation),
            publicKey: publicKey
        )
        let invalidSet = try Alpha.BCHSignatureSet(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot:
                preparation.transcript.transcriptRoot.validatedBytes,
            submissions: [
                try .init(
                    transcriptRoot:
                        preparation.transcript.transcriptRoot.validatedBytes,
                    entry: invalidEntry
                )
            ],
            expectedInputCount: 1
        )
        #expect(throws: Alpha.ContractError.bchSignatureVerificationFailed(
            index: 0
        )) {
            _ = try Alpha.CompleteTransactionAssembler.assemble(
                transcript: preparation.transcript,
                signatureSet: invalidSet,
                spentInputs: [spentInput]
            )
        }
    }

    @Test("Reject transactions whose nonblank members exceed the profile")
    func rejectExcessCompleteTransactionComponents() throws {
        let publicKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 1_300).compressed
        let unlockingScript = [UInt8(0x41)]
            + [UInt8](repeating: 0x55, count: 64)
            + [UInt8(0x41), 0x21]
            + publicKey
        let lockingScript = [UInt8(0x76), 0xa9, 0x14]
            + OpalFusion.Execution.ProtocolPrimitives.hash160(publicKey)
            + [0x88, 0xac]
        let inputs = (0 ..< 92).map { index in
            OpalFusion.Execution.BCHTransaction.Input(
                previousTransactionHashLittleEndian:
                    [UInt8](repeating: UInt8(index + 1), count: 32),
                previousOutputIndex: 0,
                unlockingScript: unlockingScript,
                sequence: UInt32.max
            )
        }
        let outputs = (0 ..< 93).map { _ in
            OpalFusion.Execution.BCHTransaction.Output(
                amountSatoshis: 1,
                lockingScript: lockingScript
            )
        }
        let transaction = OpalFusion.Execution.BCHTransaction(
            version: 2,
            inputs: inputs,
            outputs: outputs,
            lockTime: 0
        )
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: transaction.serialize()
        )

        #expect(throws: Alpha.ContractError.invalidCompleteTransaction) {
            _ = try Alpha.CompleteTransactionPayload(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
                completeTransaction: complete
            )
        }
    }
}

private extension UInt32 {
    init(bigEndianBytes: [UInt8]) {
        self = bigEndianBytes.reduce(0) { ($0 << 8) | UInt32($1) }
    }
}
