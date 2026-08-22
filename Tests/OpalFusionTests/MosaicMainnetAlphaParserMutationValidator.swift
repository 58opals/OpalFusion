// MosaicMainnetAlphaParserMutationValidator.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic mainnet-alpha deterministic parser mutation validation")
struct MosaicMainnetAlphaParserMutationValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Codec = Alpha.CanonicalWireCodec
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    @Test(
        "Mutate signed Nostr events and relay server frames",
        .timeLimit(.minutes(1))
    )
    func mutateNostrEventAndRelayParsers() throws {
        let eventLimits = try Nostr.EventCodingLimits(
            maximumEventJSONByteCount: 8_192,
            maximumTagCount: 16,
            maximumTagElementCount: 8,
            maximumStringByteCount: 4_096
        )
        let relayLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: 16_384,
            maximumFiltersPerRequest: 4,
            maximumValuesPerFilter: 16,
            maximumMessageStringByteCount: 4_096,
            event: eventLimits
        )
        let eventJSON = MosaicNostrEventCodecValidator.officialNIP13Event
        let eventIdentifier = String(repeating: "0", count: 64)
        let unsignedTemplate = try Nostr.EventTemplate(
            createdAt: 1_700_000_100,
            kind: Alpha.nip59RumorKind,
            tags: [["d", OpalFusion.Mosaic.TransportProfile
                .nostrTorOpalMainnetAlpha.rawValue]],
            content: "Mosaic unsigned rumor",
            limits: eventLimits
        )
        let unsignedSigningKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([7])
        )
        let unsignedEvent = try Nostr.UnsignedEvent(
            publicKey: unsignedSigningKey.bip340VerificationKey,
            template: unsignedTemplate,
            limits: eventLimits
        )
        let unsignedEventJSON = try Nostr.UnsignedEventCodec.encode(
            unsignedEvent,
            limits: eventLimits
        )
        let paddedEnvelope = try OpalFusion.Mosaic.PaddedEnvelopeCodec
            .encode([0x01, 0x02, 0x03])
        let relayFrames = [
            "[\"NOTICE\",\"maintenance\"]",
            "[\"EOSE\",\"mosaic-round\"]",
            "[\"CLOSED\",\"mosaic-round\",\"expired\"]",
            "[\"OK\",\"\(eventIdentifier)\",true,\"saved\"]",
            "[\"EVENT\",\"mosaic-round\",\(eventJSON)]",
        ]
        var vectors = [
            MosaicDeterministicParserMutationVector(
                name: "signed Nostr event",
                seedBytes: Array(eventJSON.utf8)
            ) { bytes in
                let decoded = try Nostr.EventCodec.decode(
                    Data(bytes),
                    limits: eventLimits
                )
                let canonical = try Nostr.EventCodec.encode(
                    decoded,
                    limits: eventLimits
                )
                let decodedAgain = try Nostr.EventCodec.decode(
                    canonical,
                    limits: eventLimits
                )
                return try Nostr.EventCodec.encode(
                    decodedAgain,
                    limits: eventLimits
                ) == canonical
            },
            MosaicDeterministicParserMutationVector(
                name: "unsigned Nostr rumor",
                seedBytes: Array(unsignedEventJSON)
            ) { bytes in
                let decoded = try Nostr.UnsignedEventCodec.decode(
                    Data(bytes),
                    limits: eventLimits
                )
                let canonical = try Nostr.UnsignedEventCodec.encode(
                    decoded,
                    limits: eventLimits
                )
                let decodedAgain = try Nostr.UnsignedEventCodec.decode(
                    canonical,
                    limits: eventLimits
                )
                return try Nostr.UnsignedEventCodec.encode(
                    decodedAgain,
                    limits: eventLimits
                ) == canonical
            },
            MosaicDeterministicParserMutationVector(
                name: "fixed padded envelope",
                seedBytes: Array(paddedEnvelope.utf8)
            ) { bytes in
                let decoded = try OpalFusion.Mosaic.PaddedEnvelopeCodec
                    .decode(String(decoding: bytes, as: UTF8.self))
                return try OpalFusion.Mosaic.PaddedEnvelopeCodec
                    .encode(decoded).utf8.elementsEqual(bytes)
            },
        ]
        vectors.append(
            contentsOf: relayFrames.enumerated().map { index, frame in
                MosaicDeterministicParserMutationVector(
                    name: "relay server frame \(index)",
                    seedBytes: Array(frame.utf8)
                ) { bytes in
                    _ = try Nostr.RelayMessageCodec.decodeServerMessage(
                        Data(bytes),
                        limits: relayLimits
                    )
                    return true
                }
            }
        )

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x510E_527F_ADE6_82D1,
            seededMutationCount: 64
        )
    }

    @Test(
        "Mutate core post-manifest canonical wire parsers",
        .timeLimit(.minutes(1))
    )
    func mutateCorePostManifestCanonicalWireParsers() throws {
        let election = try MosaicMainnetAlphaFixtures.makeElection()
        let manifestContext = try MosaicMainnetAlphaFixtures
            .makeManifestProposalContext(election: election)
        let manifest = try MosaicMainnetAlphaFixtures.makeManifest(
            election: election,
            verificationKey: MosaicMainnetAlphaFixtures.rsaVerificationKey()
        )
        let eventKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([9])
        ).bip340VerificationKey
        let controlEnvelope = try MosaicMainnetAlphaFixtures
            .signControlEnvelope(
                scalarByte: 1,
                senderEventIdentity: [UInt8](eventKey.rawRepresentation),
                phase: .manifestAgreement,
                payloadType: .aggregateReservation,
                payload: [0x01, 0x02, 0x03]
            )
        let communicationKey = try MosaicOpalV0WireContractValidator
            .publicKeyFixture(scalar: 1_200).compressed
        let anonymousEnvelope = try Alpha.AnonymousEnvelope(
            roundIdentifier: MosaicMainnetAlphaFixtures.roundIdentifier,
            phase: .bchSigning,
            senderCommunicationPublicKey: communicationKey,
            recipientEventIdentity: MosaicManifestSignatureFixtures
                .controlIdentity(scalarByte: 9).validatedBytes,
            sequence: 0,
            payloadType: .bchSignatureSubmission,
            expiryUnixSeconds: 1_800_000_060,
            payload: [0xAA]
        )
        let componentSet = try MosaicUnsignedTransactionTranscriptFixtures
            .makeBalancedComponentSet(
                contributorCount: election.result.roster.contributors.count,
                profile: .opalMainnetAlpha
            )
        let componentBytes = OpalFusion.Mosaic.OpalV0.CanonicalWireCodec
            .encodeComponentSet(componentSet)
        let reservation = try Alpha.AggregateReservation(
            aggregateKind: .componentSet,
            aggregateDigest: componentSet.digest,
            declaredCanonicalByteCount: componentBytes.count
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
        let fragmentBodyByteCount = try #require(
            reservation.expectedBodyByteCount(at: 0)
        )
        let aggregateFragment = try Alpha.AggregateFragment(
            reservationSequence: 10,
            fragmentIndex: 0,
            body: Array(componentBytes.prefix(fragmentBodyByteCount)),
            reservation: reservation
        )
        let authorizationToken = try MosaicMainnetAlphaFixtures
            .makeAuthorizationToken(
                purpose: .bchSignature,
                binding: [UInt8](repeating: 0x91, count: 32)
            )
        let transcriptRoot = try Attempt.TranscriptRoot(
            validating: MosaicMainnetAlphaFixtures.transcriptRoot
        )
        let acknowledgements = MosaicManifestSignatureFixtures
            .transcriptAcknowledgements(
                for: election.result.roster.contributors,
                binding: manifest.binding,
                transcriptRoot: transcriptRoot,
                profile: .opalMainnetAlpha
            )
            .sorted {
                $0.contributor.validatedBytes.lexicographicallyPrecedes(
                    $1.contributor.validatedBytes
                )
            }
        let acknowledgementSubmissions = try acknowledgements.map {
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
            submissions: acknowledgementSubmissions
        )
        let bchSigningKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([11])
        )
        let bchSignature = try bchSigningKey.signSchnorr(
            digest: .init(
                rawRepresentation: Data(repeating: 0x51, count: 32)
            )
        )
        let bchEntry = try Alpha.BCHSignatureEntry(
            inputIndex: 0,
            signature: [UInt8](bchSignature.rawRepresentation),
            publicKey: [UInt8](
                bchSigningKey.publicKey.compressedRepresentation
            )
        )
        let bchSubmission = try Alpha.BCHSignatureSubmission(
            transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
            authorizationToken: authorizationToken,
            entry: bchEntry
        )
        let bchSignatureSet = try Alpha.BCHSignatureSet(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
            entries: [bchEntry],
            expectedInputCount: 1
        )
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "round manifest",
                seedBytes: Codec.encodeManifest(manifest)
            ) { bytes in
                let decoded = try Codec.decodeManifest(
                    from: bytes,
                    expectedContext: manifestContext
                )
                return Codec.encodeManifest(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "control envelope",
                seedBytes: try Codec.encodeControlEnvelope(
                    controlEnvelope
                )
            ) { bytes in
                let decoded = try Codec.decodeControlEnvelope(from: bytes)
                return try Codec.encodeControlEnvelope(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "anonymous envelope",
                seedBytes: try Codec.encodeAnonymousEnvelope(
                    anonymousEnvelope
                )
            ) { bytes in
                let decoded = try Codec.decodeAnonymousEnvelope(from: bytes)
                return try Codec.encodeAnonymousEnvelope(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "aggregate reservation",
                seedBytes: try Codec.encodeAggregateReservation(
                    reservation
                )
            ) { bytes in
                let decoded = try Codec.decodeAggregateReservation(from: bytes)
                return try Codec.encodeAggregateReservation(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "player commit",
                seedBytes: Codec.encodePlayerCommit(playerCommit)
            ) { bytes in
                let decoded = try Codec.decodePlayerCommit(from: bytes)
                return Codec.encodePlayerCommit(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "aggregate fragment",
                seedBytes: try Codec.encodeAggregateFragment(
                    aggregateFragment
                )
            ) { bytes in
                let decoded = try Codec.decodeAggregateFragment(
                    from: bytes,
                    reservation: reservation
                )
                return try Codec.encodeAggregateFragment(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "authorization token",
                seedBytes: try Codec.encodeAuthorizationToken(
                    authorizationToken
                )
            ) { bytes in
                let decoded = try Codec.decodeAuthorizationToken(from: bytes)
                return try Codec.encodeAuthorizationToken(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "pre-sign acknowledgement submission",
                seedBytes: Codec.encodePreSignAcknowledgementSubmission(
                    acknowledgementSubmissions[0]
                )
            ) { bytes in
                let decoded = try Codec
                    .decodePreSignAcknowledgementSubmission(
                        from: bytes,
                        contributor: acknowledgementSubmissions[0]
                            .acknowledgement.contributor
                    )
                return Codec.encodePreSignAcknowledgementSubmission(decoded)
                    == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "pre-sign acknowledgement set",
                seedBytes: Codec.encodePreSignAcknowledgementSet(
                    acknowledgementSet
                )
            ) { bytes in
                let decoded = try Codec.decodePreSignAcknowledgementSet(
                    from: bytes,
                    roster: election.result.roster
                )
                return Codec.encodePreSignAcknowledgementSet(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "BCH signature submission",
                seedBytes: Codec.encodeBCHSignatureSubmission(
                    bchSubmission
                )
            ) { bytes in
                let decoded = try Codec.decodeBCHSignatureSubmission(
                    from: bytes
                )
                return Codec.encodeBCHSignatureSubmission(decoded) == bytes
            },
            MosaicDeterministicParserMutationVector(
                name: "BCH signature set",
                seedBytes: Codec.encodeBCHSignatureSet(bchSignatureSet)
            ) { bytes in
                let decoded = try Codec.decodeBCHSignatureSet(
                    from: bytes,
                    expectedInputCount: 1
                )
                return Codec.encodeBCHSignatureSet(decoded) == bytes
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x1F83_D9AB_FB41_BD6B,
            seededMutationCount: 64
        )
    }

    @Test(
        "Mutate private-alpha recovery snapshots",
        .timeLimit(.minutes(1))
    )
    func mutatePrivateAlphaRecoverySnapshots() async throws {
        let binding = try Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x61, count: 32),
            generationIdentifier: Data(repeating: 0x62, count: 32),
            materialIdentifier: Data(repeating: 0x63, count: 32)
        )
        let fresh = try Runtime.createFreshAttempt(
            boundTo: binding,
            discoveryEpochStartUnixSeconds: 1_800_000_000
        )
        let owner = try Runtime.Owner(claiming: fresh)
        guard case let .persist(transition) = try await owner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let vector = MosaicDeterministicParserMutationVector(
            name: "fresh runtime recovery snapshot",
            seedBytes: Array(transition.replacementSnapshot)
        ) { bytes in
            let decoded = try Runtime.RecoveryState.decode(
                from: Data(bytes),
                expectedBinding: binding
            )
            return try decoded.canonicalBytes() == Data(bytes)
        }

        try MosaicDeterministicParserMutationCampaign.validate(
            [vector],
            seed: 0x5BE0_CD19_137E_2179,
            seededMutationCount: 64
        )
    }
}
