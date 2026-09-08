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
    typealias OpalV0 = OpalFusion.Mosaic.OpalV0
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
        "Mutate Opal v0 canonical wire parsers",
        .timeLimit(.minutes(1))
    )
    func mutateOpalV0CanonicalWireParsers() throws {
        typealias OpalV0Codec = OpalV0.CanonicalWireCodec

        let authorizationRequest = try OpalV0.AuthorizationRequestPayload(
            slot: 7,
            blindedMessage: .init(
                rawRepresentation: Data(repeating: 0xAA, count: 256)
            )
        )
        let authorizationResponse = try OpalV0.AuthorizationResponsePayload(
            slot: 22,
            blindSignature: .init(
                rawRepresentation: Data(repeating: 0xBB, count: 256)
            )
        )
        let authorizationToken = try MosaicOpalV0WireContractValidator
            .makeAuthorizationToken()
        let componentCommitment = try MosaicOpalV0WireContractValidator
            .makeCommitment(index: 9)
        let groupedCommitment = try MosaicOpalV0WireContractValidator
            .makeGroupedCommitment()
        let inputComponent = try MosaicOpalV0WireContractValidator
            .makeInputComponent()
        let outputComponent = try MosaicOpalV0WireContractValidator
            .makeOutputComponent()
        let blankComponent = try MosaicOpalV0WireContractValidator
            .makeBlankComponent(index: 9)
        let anonymousComponent = try OpalV0.AnonymousComponentPayload(
            roundIdentifier: [UInt8](repeating: 0x11, count: 32),
            authorizationToken: authorizationToken,
            component: blankComponent
        )
        let acknowledgement = try OpalV0.PreSignAcknowledgementPayload(
            roundIdentifier: [UInt8](repeating: 0x11, count: 32),
            transcriptRoot: [UInt8](repeating: 0x22, count: 32)
        )
        let commitmentSet = try MosaicOpalV0WireContractValidator
            .makeCommitmentSet()
        let componentSet = try MosaicOpalV0WireContractValidator
            .makeBlankComponentSet()
        let aggregateFragment = try #require(
            OpalV0.AggregateFragmenter.fragments(
                for: commitmentSet,
                roundIdentifier: MosaicOpalV0WireContractValidator
                    .aggregateFragmentRoundIdentifier
            ).first
        )
        let vectors = try [
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 authorization request",
                value: authorizationRequest,
                encode: OpalV0Codec.encodeAuthorizationRequest,
                decode: OpalV0Codec.decodeAuthorizationRequest
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 authorization response",
                value: authorizationResponse,
                encode: OpalV0Codec.encodeAuthorizationResponse,
                decode: OpalV0Codec.decodeAuthorizationResponse
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 authorization token",
                value: authorizationToken,
                encode: OpalV0Codec.encodeAuthorizationToken,
                decode: { try OpalV0Codec.decodeAuthorizationToken(from: $0) }
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 component commitment",
                value: componentCommitment,
                encode: OpalV0Codec.encodeComponentCommitment,
                decode: OpalV0Codec.decodeComponentCommitment
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 grouped commitment",
                value: groupedCommitment,
                encode: OpalV0Codec.encodeGroupedCommitment,
                decode: OpalV0Codec.decodeGroupedCommitment
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 input component",
                value: inputComponent,
                encode: OpalV0Codec.encodeComponent,
                decode: OpalV0Codec.decodeComponent
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 output component",
                value: outputComponent,
                encode: OpalV0Codec.encodeComponent,
                decode: OpalV0Codec.decodeComponent
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 blank component",
                value: blankComponent,
                encode: OpalV0Codec.encodeComponent,
                decode: OpalV0Codec.decodeComponent
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 anonymous component",
                value: anonymousComponent,
                encode: OpalV0Codec.encodeAnonymousComponent,
                decode: { try OpalV0Codec.decodeAnonymousComponent(from: $0) }
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 pre-sign acknowledgement",
                value: acknowledgement,
                encode: OpalV0Codec.encodePreSignAcknowledgement,
                decode: OpalV0Codec.decodePreSignAcknowledgement
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 commitment set",
                value: commitmentSet,
                encode: OpalV0Codec.encodeCommitmentSet,
                decode: { try OpalV0Codec.decodeCommitmentSet(from: $0) }
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 component set",
                value: componentSet,
                encode: OpalV0Codec.encodeComponentSet,
                decode: { try OpalV0Codec.decodeComponentSet(from: $0) }
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "Opal v0 aggregate fragment",
                value: aggregateFragment,
                encode: OpalV0Codec.encodeAggregateFragment,
                decode: OpalV0Codec.decodeAggregateFragment
            ),
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x6A09_E667_F3BC_C909,
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
        let componentAuthorizationResponses = try (0 ..< Alpha
            .componentCountPerContributor).map { slot in
                try OpalV0.AuthorizationResponsePayload(
                    slot: slot,
                    blindSignature: .init(
                        rawRepresentation: Data(
                            repeating: UInt8(slot + 1),
                            count: OpalV0.authorizationMaterialByteCount
                        )
                    )
                )
            }
        let bchSignatureAuthorizationResponses = try (0 ..< Alpha
            .componentCountPerContributor).map { slot in
                try OpalV0.AuthorizationResponsePayload(
                    slot: slot,
                    blindSignature: .init(
                        rawRepresentation: Data(
                            repeating: UInt8(slot + 0x41),
                            count: OpalV0.authorizationMaterialByteCount
                        )
                    )
                )
            }
        let authorizationResponseSet = try Alpha.AuthorizationResponseSet(
            roundIdentifier: playerCommit.roundIdentifier,
            contributor: playerCommit.contributor,
            playerCommitDigest: playerCommit.digest,
            componentAuthorizationResponses: componentAuthorizationResponses,
            bchSignatureAuthorizationResponses:
                bchSignatureAuthorizationResponses
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
        let anonymousComponentValue = try MosaicOpalV0WireContractValidator
            .makeBlankComponent(index: 99)
        let anonymousComponent = try Alpha.AnonymousComponentPayload(
            roundIdentifier: manifest.binding.roundIdentifier,
            authorizationToken: MosaicMainnetAlphaFixtures
                .makeAuthorizationToken(
                    purpose: .component,
                    binding: Alpha.AuthorizationTokenInput.componentBinding(
                        for: anonymousComponentValue
                    ),
                    roundIdentifier: manifest.binding.roundIdentifier
                ),
            component: anonymousComponentValue
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
        let completeTransactionPublicKey = try
            MosaicOpalV0WireContractValidator.publicKeyFixture(
                scalar: 1_300
            ).compressed
        let completeTransaction = OpalFusion.Execution.BCHTransaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHashLittleEndian:
                        [UInt8](repeating: 0x31, count: 32),
                    previousOutputIndex: 0,
                    unlockingScript: [0x41]
                        + [UInt8](repeating: 0x52, count: 64)
                        + [0x41, 0x21]
                        + completeTransactionPublicKey,
                    sequence: UInt32.max
                ),
            ],
            outputs: [
                .init(
                    amountSatoshis: 1,
                    lockingScript: MosaicOpalV0WireContractValidator
                        .p2pkhLockingScript(fill: 0x73)
                ),
            ],
            lockTime: 0
        )
        let completeTransactionPayload = try Alpha.CompleteTransactionPayload(
            roundIdentifier: manifest.binding.roundIdentifier,
            transcriptRoot: MosaicMainnetAlphaFixtures.transcriptRoot,
            completeTransaction: .init(
                transactionBytes: completeTransaction.serialize()
            )
        )
        let vectors = [
            MosaicDeterministicParserMutationVector(
                name: "round manifest core",
                seedBytes: try Codec.encodeManifestCore(manifest.core)
            ) { bytes in
                let decoded = try Codec.decodeManifestCore(
                    from: bytes,
                    expectedContext: manifestContext
                )
                return try Codec.encodeManifestCore(decoded) == bytes
            },
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
                name: "authorization response set",
                seedBytes: Codec.encodeAuthorizationResponseSet(
                    authorizationResponseSet
                )
            ) { bytes in
                let decoded = try Codec.decodeAuthorizationResponseSet(
                    from: bytes
                )
                return Codec.encodeAuthorizationResponseSet(decoded) == bytes
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
                name: "anonymous component",
                seedBytes: try Codec.encodeAnonymousComponent(
                    anonymousComponent
                )
            ) { bytes in
                let decoded = try Codec.decodeAnonymousComponent(from: bytes)
                return try Codec.encodeAnonymousComponent(decoded) == bytes
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
            MosaicDeterministicParserMutationVector(
                name: "complete transaction payload",
                seedBytes: Codec.encodeCompleteTransactionPayload(
                    completeTransactionPayload
                )
            ) { bytes in
                let decoded = try Codec.decodeCompleteTransactionPayload(
                    from: bytes
                )
                return Codec.encodeCompleteTransactionPayload(decoded)
                    == bytes
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x1F83_D9AB_FB41_BD6B,
            seededMutationCount: 64
        )
    }

    @Test(
        "Mutate private-alpha terminal recovery parsers",
        .timeLimit(.minutes(1))
    )
    func mutatePrivateAlphaTerminalRecoveryParsers() throws {
        let binding = try Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x71, count: 32),
            generationIdentifier: Data(repeating: 0x72, count: 32),
            materialIdentifier: Data(repeating: 0x73, count: 32)
        )
        let eventLimits = try Nostr.EventCodingLimits(
            maximumEventJSONByteCount: 200_000,
            maximumTagCount: 1,
            maximumTagElementCount: 2,
            maximumStringByteCount: 150_000
        )
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([9])
        )
        let signedEvent = try Nostr.EventSigner.sign(
            .init(
                createdAt: 1_800_000_000,
                kind: Alpha.nip59RumorKind,
                tags: [["p", String(repeating: "a", count: 64)]],
                content: "terminal recovery parser seed",
                limits: eventLimits
            ),
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0x79, count: 32)
            ),
            limits: eventLimits
        )
        let event = try Runtime.PrivateDeploymentEvent(
            canonicalEventBytes: try Nostr.EventCodec.encode(
                signedEvent,
                limits: eventLimits
            ),
            acceptedAtUnixSeconds: 1_800_000_000
        )
        let abortRecord = Runtime.PostManifestTerminalRecord.abort(
            binding: binding,
            phase: .walletReservation,
            event: event,
            wasReceived: true
        )
        let completionRecord = Runtime.PostManifestTerminalRecord.completion(
            binding: binding,
            event: event
        )
        let evidence = try Runtime.PostManifestTerminalEvidence(
            binding: binding,
            reason: .aborted,
            wasReceived: true,
            predecessorRevision: 7,
            predecessorSnapshotDigest: Data(repeating: 0x74, count: 32),
            localControlIdentity: Data(repeating: 0x75, count: 32),
            terminalIdentity: Data(repeating: 0x76, count: 32),
            event: event,
            admissionSnapshotDigest: Data(repeating: 0x77, count: 32),
            publicationSnapshotDigest: Data(repeating: 0x78, count: 32)
        )
        let vectors = try [
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "private-deployment event recovery",
                value: event,
                encode: { Array(try $0.canonicalRecoveryBytes()) },
                decode: {
                    try Runtime.PrivateDeploymentEvent.decodeRecoveryBytes(
                        Data($0)
                    )
                }
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "post-manifest abort terminal record",
                value: abortRecord,
                encode: { Array(try $0.canonicalBytes()) },
                decode: {
                    try Runtime.PostManifestTerminalRecord.decode(
                        Data($0),
                        expectedBinding: binding
                    )
                }
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "post-manifest completion terminal record",
                value: completionRecord,
                encode: { Array(try $0.canonicalBytes()) },
                decode: {
                    try Runtime.PostManifestTerminalRecord.decode(
                        Data($0),
                        expectedBinding: binding
                    )
                }
            ),
            MosaicDeterministicParserMutationVector.canonicalRoundTrip(
                name: "post-manifest terminal evidence",
                value: evidence,
                encode: { Array(try $0.canonicalBytes()) },
                decode: {
                    try Runtime.PostManifestTerminalEvidence.decode(
                        Data($0),
                        expectedBinding: binding
                    )
                }
            ),
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0x6A09_E667_F3BC_C909,
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

    @Test(
        "Mutate validated private-alpha recovery snapshots",
        .timeLimit(.minutes(1))
    )
    func mutateValidatedPrivateAlphaRecoverySnapshots() throws {
        let fixture = try MosaicG4PinnedParserFixture.load()
        let proof = try MosaicG4PinnedParserFixture.restoreProof()
        let binding = try Runtime.Binding(
            attemptIdentifier: Data(repeating: 0x64, count: 32),
            generationIdentifier: Data(repeating: 0x65, count: 32),
            materialIdentifier: Data(repeating: 0x66, count: 32)
        )
        let state = Runtime.RecoveryState(
            binding: binding,
            revision: 50,
            discoveryEpochStartUnixSeconds: fixture.epoch,
            phase: .walletReservation,
            preManifestDocuments: proof.canonicalDocuments,
            preManifestAbortCause: .none,
            manifestState: .validated(
                privateManifestProposalBytes: Data(
                    proof.proposalValidation.canonicalBody
                ),
                completeManifestBytes: Data(
                    proof.completeManifest.canonicalBytes
                )
            ),
            postManifestJournalState: .initialized,
            publicationState: .none,
            terminalState: .active
        )
        let snapshot = Array(try state.canonicalBytes())
        func validateSnapshot(_ bytes: [UInt8]) throws -> Bool {
            let decoded = try Runtime.RecoveryState.decode(
                from: Data(bytes),
                expectedBinding: binding
            )
            return try decoded.canonicalBytes() == Data(bytes)
        }
        #expect(try validateSnapshot(snapshot))

        let phaseOffset = 4 + 2 + (32 * 3)
        let abortCauseOffset = phaseOffset + 1 + 8 + 8 + 4
            + proof.canonicalDocuments.reduce(0) {
                $0 + 4 + $1.count
            }
        let manifestStateOffset = abortCauseOffset + 1
        let proposalBytes = proof.proposalValidation.canonicalBody
        let manifestBytes = proof.completeManifest.canonicalBytes
        let journalStateOffset = manifestStateOffset + 1
            + 4 + proposalBytes.count
            + 4 + manifestBytes.count
        let publicationStateOffset = journalStateOffset + 1
        let terminalStateOffset = publicationStateOffset + 1
        #expect(terminalStateOffset == snapshot.count - 1)

        for offset in [
            phaseOffset,
            abortCauseOffset,
            manifestStateOffset,
            journalStateOffset,
            publicationStateOffset,
            terminalStateOffset,
        ] {
            var mutation = snapshot
            mutation[offset] = .max
            #expect(throws: Runtime.Failure.malformedRecoverySnapshot) {
                _ = try validateSnapshot(mutation)
            }
        }
    }
}
