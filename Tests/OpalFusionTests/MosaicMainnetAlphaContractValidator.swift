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

    @Test("Freeze the additive profile without changing the default")
    func freezeProfile() {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let configuration = OpalFusion.Mosaic.Configuration(profile: profile)

        #expect(profile.rawValue == "Mosaic/0-opal-mainnet-alpha.4")
        #expect(profile.protocolVersion == .opalMainnetAlpha)
        #expect(profile.transportProfile == .nostrTorOpalMainnetAlpha)
        #expect(profile.rosterPolicy == .opalMainnetAlpha)
        #expect(
            profile.transactionProfileIdentifier
                == "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.4"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                profile.networkGenesisHash ?? []
            ) == "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        )
        #expect(configuration.profile == profile)
        #expect(OpalFusion.Mosaic.Configuration().profile == .draft1)
        #expect(OpalFusion.Mosaic.Profile.opalV0.rawValue == "Mosaic/0-opal.1")
        #expect(
            OpalFusion.Mosaic.Profile(
                rawValue: "Mosaic/0-opal-mainnet-alpha.3"
            ) == nil
        )
        #expect(
            OpalFusion.Mosaic.ProtocolVersion(
                rawValue: "Mosaic/0-opal-mainnet-alpha.3"
            ) == nil
        )
        #expect(
            OpalFusion.Mosaic.TransportProfile(
                rawValue: "nostr-tor/0-opal-mainnet-alpha.3"
            ) == nil
        )
        #expect(
            OpalFusion.Mosaic.TransportProfile(
                rawValue: "nostr-tor/0-opal-mainnet-alpha.4"
            ) == nil
        )
        #expect(
            [6, 7, 8].map { contributorCount in
                contributorCount * Alpha.componentCountPerContributor
            } == [138, 161, 184]
        )
    }

    @Test("Derive and validate the frozen role hash documents")
    func deriveRoleHashDocuments() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()

        #expect(election.validation.roleSeed.count == 32)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                election.commitments[0].commitment
            ) == "4ca7c2a03624c884c74ade6f632f3426eed2562aa594fe894cd59be51981cff3"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                election.validation.roleSeed
            ) == "596088c9c4ec003c0b09d988a798dc52aff5d6f570caf3896a9a49ef60dd25c1"
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
            manifest.core.componentAuthorizationVerificationKey
                .subjectPublicKeyInfo.count
                == Alpha.authorizationVerificationKeyByteCount
        )
        #expect(
            manifest.core.bchSignatureAuthorizationVerificationKey
                .subjectPublicKeyInfo.count
                == Alpha.authorizationVerificationKeyByteCount
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                manifest.core.roundIdentifier
            ) == "825a00a2b428500c20e37be0c4cb47fd81b9c3c91ae1d51f3b3245a6c60d568a"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                manifest.binding.manifestDigest
            ) == "04557e181ee962834a1262394475c3dbfd2b1b263ceb4bf75d46df375aa1769e"
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

        var oldTransport = Data(encoded)
        let transportRange = try #require(
            oldTransport.range(
                of: Data(
                    OpalFusion.Mosaic.TransportProfile
                        .nostrTorOpalMainnetAlpha.rawValue.utf8
                )
            )
        )
        oldTransport.replaceSubrange(
            transportRange,
            with: Data("nostr-tor/0-opal-mainnet-alpha.4".utf8)
        )
        #expect(throws: Alpha.ContractError.transportProfileMismatch) {
            _ = try Codec.decodeManifest(
                from: [UInt8](oldTransport),
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
        #expect(throws: Alpha.ContractError
            .duplicateBlindSigningKeyIdentifier) {
            _ = try MosaicMainnetAlphaFixtures.makeManifestCore(
                election: election,
                verificationKey:
                    manifest.core.componentAuthorizationVerificationKey,
                bchSignatureVerificationKey:
                    manifest.core.componentAuthorizationVerificationKey
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
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let playerCommit = try Alpha.PlayerCommit(
            roundIdentifier: manifest.core.roundIdentifier,
            contributor: election.result.roster.contributors[0],
            groupedCommitment: MosaicOpalV0WireContractValidator
                .makeMainnetGroupedCommitment(),
            componentAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(),
            bchSignatureAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(byteOffset: 0x40)
        )
        let decoded = try Codec.decodePlayerCommit(
            from: Codec.encodePlayerCommit(playerCommit)
        )
        let semanticValidation = try Alpha.PlayerCommitSemanticValidation(
            validating: playerCommit,
            against: manifest
        )
        #expect(decoded == playerCommit)
        #expect(semanticValidation.requiredExcessFeeSatoshis == 2)
        #expect(playerCommit.canonicalBytes.count == 14_928)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                [UInt8](
                    OpalCrypto.Hashing.sha256(
                        Data(playerCommit.canonicalBytes)
                    )
                )
            ) == "832d69a5fe48e6193f434ffc90d0c03d0674f19de74a38bcb937db2be22cb53f"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                playerCommit.digest
            ) == "83380355ea2021e6b072cd2c9771e04dd2e54484aed3ad68cfb1dd10cee6058e"
        )

        var requests = try MosaicMainnetAlphaFixtures.makeAuthorizationRequests()
        requests.swapAt(0, 1)
        #expect(throws: Alpha.ContractError.invalidAuthorizationRequestSlot(
            expected: 0,
            actual: 1
        )) {
            _ = try Alpha.PlayerCommit(
                roundIdentifier: manifest.core.roundIdentifier,
                contributor: election.result.roster.contributors[0],
                groupedCommitment: MosaicOpalV0WireContractValidator
                    .makeMainnetGroupedCommitment(),
                componentAuthorizationRequests: requests,
                bchSignatureAuthorizationRequests: MosaicMainnetAlphaFixtures
                    .makeAuthorizationRequests(byteOffset: 0x40)
            )
        }
        var bchSignatureRequests = try MosaicMainnetAlphaFixtures
            .makeAuthorizationRequests(byteOffset: 0x40)
        bchSignatureRequests.swapAt(0, 1)
        #expect(throws: Alpha.ContractError.invalidAuthorizationRequestSlot(
            expected: 0,
            actual: 1
        )) {
            _ = try Alpha.PlayerCommit(
                roundIdentifier: manifest.core.roundIdentifier,
                contributor: election.result.roster.contributors[0],
                groupedCommitment: MosaicOpalV0WireContractValidator
                    .makeMainnetGroupedCommitment(),
                componentAuthorizationRequests:
                    MosaicMainnetAlphaFixtures.makeAuthorizationRequests(),
                bchSignatureAuthorizationRequests: bchSignatureRequests
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
            ) == "eff597b3a102940381ee32ecc4500ed577b5c68b6b2d0bedc6b0c7e907c0b26f"
        )
        let encodedEnvelopeDigest = MosaicOpalV0WireContractValidator
            .hexadecimal(
                [UInt8](OpalCrypto.Hashing.sha256(
                    Data(try Codec.encodeControlEnvelope(envelope))
                ))
            )
        #expect(
            encodedEnvelopeDigest
                == "44f4b63c68255685b47fb073b2ca55195056bf133fc21805068aa96e72143389"
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
                == "7fd03084d7b576d4bf1bd6d475d14934ecce996ca1e8b56bc5c44e3b0dcd92d2"
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
            authorizationToken: MosaicMainnetAlphaFixtures
                .makeAuthorizationToken(
                    purpose: .bchSignature,
                    binding: [UInt8](repeating: 0x91, count: 32)
                ),
            entry: entry
        )
        #expect(
            try Codec.decodeBCHSignatureSubmission(
                from: Codec.encodeBCHSignatureSubmission(submission)
            ) == submission
        )
        let expectedSignature = MosaicOpalV0WireContractValidator.bytes(
            hexadecimal: "73888a05449ec95a71f9d472616d4e5cdc9638e95fce8865c09e3f4b4d7becdf426b976fceba09b92023b32fb47756fe15e3e5cb6a21713d2469f3b0a64a2c04"
        )
        let expectedPublicKey = MosaicOpalV0WireContractValidator.bytes(
            hexadecimal: "03774ae7f858a9411e5ef4246b70c65aac5649980be5c17891bbec17895da008cb"
        )
        let expectedTokenBytes = [UInt8](repeating: 0x71, count: 32)
            + [UInt8](repeating: 0x81, count: 32)
            + [Alpha.AuthorizationPurpose.bchSignature.rawValue]
            + [UInt8](repeating: 0x82, count: 32)
            + [UInt8](repeating: 0x91, count: 32)
            + [UInt8](repeating: 0x83, count: 32)
            + [UInt8](repeating: 0x84, count: 256)
        #expect(entry.signature == expectedSignature)
        #expect(entry.publicKey == expectedPublicKey)
        #expect(submission.canonicalBytes.count == 550)
        #expect(
            submission.canonicalBytes
                == [UInt8](repeating: 0x72, count: 32)
                    + expectedTokenBytes
                    + [0, 0, 0, 0]
                    + expectedSignature
                    + expectedPublicKey
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                submission.digest
            ) == "75f6290e05635e5496b4bee6746ba8cca16ac3e3b9161649d616b4caabfa3ba4"
        )
        let signatureSet = try Alpha.BCHSignatureSet(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
            entries: [submission.entry],
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
            ) == "5204ff8d5527a3b562b7809054fdb58d60da4e49cdd05360fe1c6a3af02c715f"
        )
        #expect(signatureSet.entries.map(\.inputIndex) == [0])
        #expect(throws: Alpha.ContractError.invalidSignatureSetCount(
            expected: 2,
            actual: 1
        )) {
            _ = try Alpha.BCHSignatureSet(
                roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
                transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
                entries: [submission.entry],
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
                .makeMainnetGroupedCommitment(),
            componentAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(),
            bchSignatureAuthorizationRequests: MosaicMainnetAlphaFixtures
                .makeAuthorizationRequests(byteOffset: 0x40)
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
            componentAuthorizationRequests:
                playerCommit.componentAuthorizationRequests,
            bchSignatureAuthorizationRequests:
                playerCommit.bchSignatureAuthorizationRequests
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
            componentAuthorizationRequests:
                playerCommit.componentAuthorizationRequests,
            bchSignatureAuthorizationRequests:
                playerCommit.bchSignatureAuthorizationRequests
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

    @Test("Reject BCH signatures at the component admission boundary")
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
                componentAuthorizationVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey()
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
                componentAuthorizationVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey()
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
                componentAuthorizationVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey()
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
                componentAuthorizationVerificationKey:
                    MosaicMainnetAlphaFixtures.rsaVerificationKey()
            )
        }
    }

    @Test("Freeze mainnet-alpha authorization and transcript bindings")
    func freezeAuthorizationAndTranscriptBindings() throws {
        let tokenInput = try Alpha.AuthorizationTokenInput(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            keyIdentifier: [UInt8](repeating: 0x81, count: 32),
            purpose: .component,
            nonce: [UInt8](repeating: 0x82, count: 32),
            binding: [UInt8](repeating: 0x83, count: 32)
        )
        let expectedTokenInput = "000000314d6f736169632f302d6f70616c2d6d61696e6e65742d616c7068612e342f617574686f72697a6174696f6e2f696e70757400000020000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f00000020717171717171717171717171717171717171717171717171717171717171717100000020818181818181818181818181818181818181818181818181818181818181818100000000208282828282828282828282828282828282828282828282828282828282828282000000208383838383838383838383838383838383838383838383838383838383838383"
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                tokenInput.canonicalBytes
            ) == expectedTokenInput
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                tokenInput.spentIdentifier
            ) == "bcbe2ff656cb9e623384bab07810d82d3e848b28739acdc1aeb5cbf577abc56a"
        )
        let opalV0Input = try OpalFusion.Mosaic.OpalV0.AuthorizationTokenInput(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            keyIdentifier: [UInt8](repeating: 0x81, count: 32),
            nonce: [UInt8](repeating: 0x82, count: 32)
        )
        #expect(tokenInput.spentIdentifier != opalV0Input.spentIdentifier)

        let component = try MosaicOpalV0WireContractValidator
            .makeBlankComponent(index: 9)
        let componentBinding = try Alpha.AuthorizationTokenInput
            .componentBinding(for: component)
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(componentBinding)
                == "abb0cb0afca418f3e0e5c9e2cd41a3b057718ae103864cf69481df0557ec4ea7"
        )
        let signatureInput = try Alpha.AuthorizationTokenInput(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            keyIdentifier: [UInt8](repeating: 0x81, count: 32),
            purpose: .bchSignature,
            nonce: [UInt8](repeating: 0x82, count: 32),
            binding: componentBinding
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                signatureInput.canonicalBytes
            ) == "000000314d6f736169632f302d6f70616c2d6d61696e6e65742d616c7068612e342f617574686f72697a6174696f6e2f696e70757400000020000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f0000002071717171717171717171717171717171717171717171717171717171717171710000002081818181818181818181818181818181818181818181818181818181818181810100000020828282828282828282828282828282828282828282828282828282828282828200000020abb0cb0afca418f3e0e5c9e2cd41a3b057718ae103864cf69481df0557ec4ea7"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                signatureInput.spentIdentifier
            ) == "375a6553f57163ed6182b5150f86de805a3bce0b1b1fe038892c96d932c850cf"
        )
        let signatureToken = try MosaicMainnetAlphaFixtures
            .makeAuthorizationToken(
                purpose: .bchSignature,
                binding: componentBinding
            )
        let signatureTokenBytes = try Codec.encodeAuthorizationToken(
            signatureToken
        )
        #expect(signatureTokenBytes.count == 417)
        #expect(
            signatureTokenBytes
                == [UInt8](repeating: 0x71, count: 32)
                    + [UInt8](repeating: 0x81, count: 32)
                    + [Alpha.AuthorizationPurpose.bchSignature.rawValue]
                    + [UInt8](repeating: 0x82, count: 32)
                    + componentBinding
                    + [UInt8](repeating: 0x83, count: 32)
                    + [UInt8](repeating: 0x84, count: 256)
        )

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
            ) == "81c3da65e8b6305298e5ef18a4b59a6dd8c594c4970323a10bc0c5d74ddfc2f5"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                preparation.componentSet.digest
            ) == "f454641ada837bbf3162e5f792621f5d121996a172e0bf572b0ab077207ee5d0"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                preparation.transcript.transcriptRoot.validatedBytes
            ) == "ef157b80c698b15a1e942acb8f3836f844e72a1b005ced88318a34b95fdfb2f9"
        )
        #expect(
            MosaicOpalV0WireContractValidator.hexadecimal(
                [UInt8](OpalCrypto.Hashing.sha256(
                    Data(preparation.transcript.unsignedTransactionBytes)
                ))
            ) == "6519f7d0bc1fc9c0717a79f5f76afb3d2235aa7cfe52b2f4d4ab0bde567bf512"
        )
    }

    @Test("Document structurally valid authorization without grouped membership")
    func admitAuthorizedOffCommitmentComponent() throws {
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
        let salt = [UInt8](repeating: 0xA4, count: 32)
        let payload = OpalFusion.Mosaic.OpalV0.ComponentPayload.blank
        let substituted = try OpalFusion.Mosaic.OpalV0.Component(
            saltCommitment: Alpha.ComponentHashing.saltCommitment(
                roundIdentifier: manifest.core.roundIdentifier,
                salt: salt
            ),
            payload: payload
        )
        let substitutedDigest = try Alpha.ComponentHashing
            .saltedComponentDigest(
                roundIdentifier: manifest.core.roundIdentifier,
                salt: salt,
                payload: payload
            )
        #expect(
            !preparation.commitmentSet.commitments
                .map(\.saltedComponentDigest)
                .contains(substitutedDigest)
        )

        var components = preparation.componentSet.components
        components[2] = substituted
        let substitutedSet = try OpalFusion.Mosaic.OpalV0.ComponentSet(
            profile: .opalMainnetAlpha,
            components: components
        )
        let substitutedTranscript = try OpalFusion.Mosaic.OpalV0
            .UnsignedTransactionTranscript(
                profile: .opalMainnetAlpha,
                roster: election.result.roster,
                manifest: manifest.binding,
                commitmentSet: preparation.commitmentValidation,
                componentSet: substitutedSet
            )
        #expect(substitutedTranscript.transaction == preparation.transcript.transaction)
        #expect(substitutedTranscript.feeSatoshis == preparation.transcript.feeSatoshis)
        #expect(
            substitutedTranscript.estimatedFinalSignedByteCount
                == preparation.transcript.estimatedFinalSignedByteCount
        )

        let evaluator = try MosaicMainnetAlphaFixtures.authorizationEvaluator()
        let verificationKey = try #require(evaluator.verificationKey)
        let input = try Alpha.AuthorizationTokenInput(
            roundIdentifier: manifest.core.roundIdentifier,
            keyIdentifier: [UInt8](verificationKey.keyIdentifier),
            purpose: .component,
            nonce: [UInt8](repeating: 0xA5, count: 32),
            binding: try Alpha.AuthorizationTokenInput.componentBinding(
                for: substituted
            )
        )
        let request = try Alpha.AuthorizationRequest(
            input: input,
            using: verificationKey
        )
        let token = try request.finalize(
            evaluator.evaluate(request.blindedMessage)
        )
        #expect(
            token.verify(
                purpose: .component,
                binding: input.binding,
                using: verificationKey
            )
        )
        let anonymousPayload = try Alpha.AnonymousComponentPayload(
            roundIdentifier: manifest.core.roundIdentifier,
            authorizationToken: token,
            component: substituted
        )
        let communicationKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 2_104).compressed
        let recipient = MosaicManifestSignatureFixtures.controlIdentity(
            scalarByte: 10
        ).validatedBytes
        let envelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: manifest.core.roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: recipient,
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: 1_800_000_060,
            payload: try Codec.encodeAnonymousComponent(anonymousPayload)
        )
        let validation = try Alpha.AnonymousComponentAdmissionValidation(
            envelope: envelope,
            roundIdentifier: manifest.core.roundIdentifier,
            authenticatedOuterEventIdentity: Array(communicationKey.dropFirst()),
            expectedRecipientEventIdentity: recipient,
            currentUnixSeconds: 1_800_000_000,
            componentAuthorizationVerificationKey: verificationKey
        )
        #expect(validation.payload.component == substituted)
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
            entries: [entry],
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
            ) == "5d932bfedfdec495df86e180b1d4d0610fc61f06229c7dff6554cf4e2252e5de"
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
            entries: [wrongAmountEntry],
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
            entries: [invalidEntry],
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
