// MosaicMainnetAlphaPostManifestNIP59TransportValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest NIP-59 transport")
struct MosaicMainnetAlphaPostManifestNIP59TransportValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Transport = Alpha.PostManifestNIP59Transport

    private let phaseStart: UInt64 = 1_700_000_000
    private let current: UInt64 = 1_700_000_100
    private let expiry: UInt64 = 1_700_001_000

    @Test("Freeze the transport-only alpha.5 selector and derived bounds")
    func freezeTransportContract() throws {
        #expect(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.rawValue
                == "Mosaic/0-opal-mainnet-alpha.4"
        )
        #expect(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha
                .transactionProfileIdentifier
                == "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.4"
        )
        #expect(
            OpalFusion.Mosaic.Profile.opalMainnetAlpha.transportProfile.rawValue
                == "nostr-tor/0-opal-mainnet-alpha.5"
        )
        #expect(Alpha.nip59RumorKind == 78)
        #expect(Alpha.nip59ApplicationContentByteCount == 8_192)
        #expect(Alpha.nip59MaximumRumorJSONByteCount == 8_448)
        #expect(Alpha.nip59SealContentByteCount == 13_744)
        #expect(Alpha.nip59MaximumSealJSONByteCount == 14_097)
        #expect(Alpha.nip59GiftWrapContentByteCount == 19_204)
        #expect(Alpha.nip59MaximumGiftWrapJSONByteCount == 19_631)
        #expect(Alpha.nip59MaximumPublicationFrameByteCount == 19_641)
        #expect(Alpha.relayCount == 3)
        #expect(Alpha.relayAcceptanceQuorum == 2)
        #expect(Alpha.anonymousEnvelopeFixedOverheadByteCount == 217)
        #expect(Alpha.maximumAnonymousPayloadByteCount == 3_875)

        let maximum = [UInt8](
            repeating: 0xAB,
            count: OpalFusion.Mosaic.PaddedEnvelopeCodec
                .maximumPayloadByteCount
        )
        #expect(
            try OpalFusion.Mosaic.PaddedEnvelopeCodec.encode(maximum)
                .utf8.count == Alpha.nip59ApplicationContentByteCount
        )
        #expect(
            throws: OpalFusion.Mosaic.PaddedEnvelopeCodec.CodingError
                .payloadTooLarge(maximum: 4_092, actual: 4_093)
        ) {
            _ = try OpalFusion.Mosaic.PaddedEnvelopeCodec.encode(
                maximum + [0x00]
            )
        }
    }

    @Test("Round-trip an authenticated control gift wrap at fixed size")
    func roundTripControl() throws {
        let eventKey = try signingKey(2)
        let recipient = try signingKey(3)
        let envelope = try controlEnvelope(
            eventSigningKey: eventKey,
            payloadCount: Alpha.maximumControlPayloadByteCount
        )
        let giftWrap = try Transport.makeControlGiftWrap(
            envelope,
            context: runtimeContext(),
            timestamps: layerTimestamps(),
            senderEventSigningKey: eventKey,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let opened = try Transport.openControl(
            giftWrap,
            context: runtimeContext(),
            recipientSigningKey: recipient,
            currentUnixSeconds: current
        )
        guard case let .control(delivery) = opened.storage else {
            Issue.record("Expected an authenticated control delivery")
            return
        }

        #expect(delivery.envelope == envelope)
        #expect(delivery.attemptIdentifier == runtimeContext().attemptIdentifier)
        #expect(delivery.generationIdentifier == runtimeContext().generationIdentifier)
        #expect(
            delivery.authenticatedOuterEventIdentity
                == Array(eventKey.bip340VerificationKey.rawRepresentation)
        )
        try assertFixedSizes(
            giftWrap,
            sender: eventKey,
            recipient: recipient
        )
    }

    @Test("Round-trip an anonymous gift wrap using its exact outer event ID")
    func roundTripAnonymous() throws {
        let sender = try signingKey(4)
        let recipient = try signingKey(5)
        let envelope = try anonymousEnvelope(
            senderSigningKey: sender,
            recipient: recipient,
            payloadCount: Alpha.maximumAnonymousPayloadByteCount
        )
        let giftWrap = try Transport.makeAnonymousGiftWrap(
            envelope,
            context: runtimeContext(),
            timestamps: layerTimestamps(),
            senderCommunicationSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let opened = try Transport.openAnonymous(
            giftWrap,
            context: runtimeContext(),
            recipientSigningKey: recipient,
            currentUnixSeconds: current
        )
        guard case let .anonymous(delivery) = opened.storage else {
            Issue.record("Expected an authenticated anonymous delivery")
            return
        }

        #expect(delivery.envelope == envelope)
        #expect(
            delivery.authenticatedOuterEventIdentity
                == Array(sender.bip340VerificationKey.rawRepresentation)
        )
        #expect(
            delivery.authenticatedRecipientEventIdentity
                == Array(recipient.bip340VerificationKey.rawRepresentation)
        )
        #expect(
            delivery.authenticatedMessageIdentifier.bytes
                == Array(giftWrap.identifier.rawRepresentation)
        )
        try assertFixedSizes(
            giftWrap,
            sender: sender,
            recipient: recipient
        )
    }

    @Test("Pin one deterministic alpha.5 control gift-wrap vector")
    func pinDeterministicControlGiftWrap() throws {
        let sender = try signingKey(19)
        let recipient = try signingKey(20)
        let wrapper = try signingKey(21)
        let envelope = try controlEnvelope(
            eventSigningKey: sender,
            payloadCount: 1
        )
        let limits = try Transport.codingLimits
        let canonicalEnvelope = try Alpha.CanonicalWireCodec
            .encodeControlEnvelope(envelope)
        let rumor = try Nostr.UnsignedEvent(
            publicKey: sender.bip340VerificationKey,
            template: .init(
                createdAt: current,
                kind: Alpha.nip59RumorKind,
                tags: [[
                    "d",
                    OpalFusion.Mosaic.TransportProfile
                        .nostrTorOpalMainnetAlpha.rawValue,
                ]],
                content: try OpalFusion.Mosaic.PaddedEnvelopeCodec.encode(
                    canonicalEnvelope
                ),
                limits: limits.event
            ),
            limits: limits.event
        )
        let rumorJSON = try Nostr.UnsignedEventCodec.encode(
            rumor,
            limits: limits.event
        )
        let seal = try deterministicEncryptedEvent(
            plaintext: String(decoding: rumorJSON, as: UTF8.self),
            kind: 13,
            tags: [],
            signingKey: sender,
            recipient: recipient,
            nonceByte: 0xD2,
            auxiliaryRandomnessByte: 0xD3,
            createdAt: current - 2,
            maximumPlaintextByteCount: limits.maximumRumorJSONByteCount,
            limits: limits
        )
        let sealJSON = try Nostr.EventCodec.encode(
            seal,
            limits: limits.event
        )
        let giftWrap = try deterministicEncryptedEvent(
            plaintext: String(decoding: sealJSON, as: UTF8.self),
            kind: Nostr.NIP59EnvelopeCodec.DeliveryKind.regular.rawValue,
            tags: [recipientTag(recipient)],
            signingKey: wrapper,
            recipient: recipient,
            nonceByte: 0xD4,
            auxiliaryRandomnessByte: 0xD5,
            createdAt: current - 1,
            maximumPlaintextByteCount: limits.maximumSealJSONByteCount,
            limits: limits
        )
        let opened = try Transport.openControl(
            giftWrap,
            context: runtimeContext(),
            recipientSigningKey: recipient,
            currentUnixSeconds: current
        )
        guard case let .control(delivery) = opened.storage else {
            Issue.record("Expected an authenticated control delivery")
            return
        }
        let giftWrapJSON = try Nostr.EventCodec.encode(
            giftWrap,
            limits: limits.event
        )
        let relayLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: Alpha.nip59MaximumPublicationFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 1_024,
            event: limits.event
        )
        let publicationFrame = try Nostr.RelayMessageCodec.encode(
            .event(giftWrap),
            limits: relayLimits
        )

        #expect(delivery.envelope == envelope)
        #expect(
            hexadecimal(OpalCrypto.Hashing.sha256(Data(canonicalEnvelope)))
                == "3f10235ba7ea4ebe80814a1a65785a18e421bbc6af350f3eca26954a2619ebd2"
        )
        #expect(
            hexadecimal(rumor.identifier.rawRepresentation)
                == "f05a19cb37c0bb83dc378a079916ed93b407189ce26796ee18d887057dbd80bc"
        )
        #expect(
            hexadecimal(seal.identifier.rawRepresentation)
                == "2a193fbb25fab39a51bada25688c4be416924badfee685fd3985fd78c2fefb19"
        )
        #expect(
            hexadecimal(giftWrap.identifier.rawRepresentation)
                == "9c96d1fffa2a389e6951284e6d054b22ee267a17776c1fa69f18e2a43a5c3897"
        )
        #expect(
            hexadecimal(OpalCrypto.Hashing.sha256(giftWrapJSON))
                == "583e13782d7b24334ae79be754ab7be8fa5737d02b5ba0a41d956e97fa8ce75e"
        )
        #expect(
            hexadecimal(OpalCrypto.Hashing.sha256(publicationFrame))
                == "3a7f23ffcf6b7f26b237412e6fbbf21fbac2bcb2077fbf132b6258f4e9a56bab"
        )
    }

    @Test("Pin full-width timestamp allocation ceilings")
    func pinMaximumTimestampSizes() throws {
        let sender = try signingKey(15)
        let recipient = try signingKey(16)
        let envelope = try controlEnvelope(
            eventSigningKey: sender,
            payloadCount: 1,
            expiryUnixSeconds: .max
        )
        let timestamps = try Transport.LayerTimestamps(
            phaseStartUnixSeconds: .max - 100,
            currentUnixSeconds: .max,
            sealCreatedAt: .max - 2,
            giftWrapCreatedAt: .max - 1
        )
        let giftWrap = try Transport.makeControlGiftWrap(
            envelope,
            context: .init(
                attemptIdentifier: runtimeContext().attemptIdentifier,
                generationIdentifier: runtimeContext().generationIdentifier,
                phaseStartUnixSeconds: .max - 100
            ),
            timestamps: timestamps,
            senderEventSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey
        )
        let limits = try Transport.codingLimits
        let opened = try Nostr.NIP59EnvelopeCodec.open(
            giftWrap,
            expectedDeliveryKind: .regular,
            expectedRumorKind: Alpha.nip59RumorKind,
            recipientSigningKey: recipient,
            limits: limits
        )
        #expect(opened.rumorJSONByteCount == Alpha.nip59MaximumRumorJSONByteCount)
        #expect(opened.sealJSONByteCount == Alpha.nip59MaximumSealJSONByteCount)
        #expect(
            try Nostr.EventCodec.encode(giftWrap, limits: limits.event).count
                == Alpha.nip59MaximumGiftWrapJSONByteCount
        )

        let relayLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: Alpha.nip59MaximumPublicationFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 1_024,
            event: limits.event
        )
        #expect(
            try Nostr.RelayMessageCodec.encode(
                .event(giftWrap),
                limits: relayLimits
            ).count == Alpha.nip59MaximumPublicationFrameByteCount
        )
    }

    @Test("Use one regular recipient filter without exposing extra tags")
    func makeRelayFilter() throws {
        let recipient = try signingKey(6).bip340VerificationKey
        let filter = try Transport.relayFilter(
            recipientPublicKey: recipient
        )
        #expect(filter.kinds == [1_059])
        #expect(filter.recipientPublicKeys == [recipient])
        #expect(filter.identifiers.isEmpty)
        #expect(filter.authors.isEmpty)
    }

    @Test("Reject invalid outbound timestamps and sender authority")
    func rejectInvalidOutboundContext() throws {
        #expect(throws: Transport.Failure.invalidLayerTimestamps) {
            _ = try Transport.LayerTimestamps(
                phaseStartUnixSeconds: phaseStart,
                currentUnixSeconds: phaseStart,
                sealCreatedAt: phaseStart,
                giftWrapCreatedAt: phaseStart
            )
        }

        let expectedSender = try signingKey(7)
        let otherSender = try signingKey(8)
        let recipient = try signingKey(9)
        let control = try controlEnvelope(
            eventSigningKey: expectedSender,
            payloadCount: 1
        )
        #expect(throws: Transport.Failure.senderIdentityMismatch) {
            _ = try Transport.makeControlGiftWrap(
                control,
                context: runtimeContext(),
                timestamps: layerTimestamps(),
                senderEventSigningKey: otherSender,
                recipientPublicKey: recipient.bip340VerificationKey
            )
        }
        let foreignContext = Transport.RuntimeContext(
            attemptIdentifier: runtimeContext().attemptIdentifier,
            generationIdentifier: runtimeContext().generationIdentifier,
            phaseStartUnixSeconds: phaseStart - 1
        )
        #expect(throws: Transport.Failure.invalidLayerTimestamps) {
            _ = try Transport.makeControlGiftWrap(
                control,
                context: foreignContext,
                timestamps: layerTimestamps(),
                senderEventSigningKey: expectedSender,
                recipientPublicKey: recipient.bip340VerificationKey
            )
        }

        let anonymous = try anonymousEnvelope(
            senderSigningKey: expectedSender,
            recipient: recipient,
            payloadCount: 1
        )
        #expect(throws: Transport.Failure.recipientIdentityMismatch) {
            _ = try Transport.makeAnonymousGiftWrap(
                anonymous,
                context: runtimeContext(),
                timestamps: layerTimestamps(),
                senderCommunicationSigningKey: expectedSender,
                recipientPublicKey: otherSender.bip340VerificationKey
            )
        }

        let expiredAtCreation = try controlEnvelope(
            eventSigningKey: expectedSender,
            payloadCount: 1,
            expiryUnixSeconds: current - 1
        )
        #expect(throws: Transport.Failure.invalidRumorTimestamp) {
            _ = try Transport.makeControlGiftWrap(
                expiredAtCreation,
                context: runtimeContext(),
                timestamps: layerTimestamps(),
                senderEventSigningKey: expectedSender,
                recipientPublicKey: recipient.bip340VerificationKey
            )
        }
    }

    @Test("Reject nonprofile delivery kinds and visible wrapper metadata")
    func rejectOuterMappingSubstitution() throws {
        let sender = try signingKey(10)
        let recipient = try signingKey(11)
        let envelope = try controlEnvelope(
            eventSigningKey: sender,
            payloadCount: 1
        )
        let bytes = try Alpha.CanonicalWireCodec.encodeControlEnvelope(envelope)
        let ephemeral = try customGiftWrap(
            canonicalEnvelope: bytes,
            sender: sender,
            recipient: recipient,
            deliveryKind: .ephemeral
        )
        #expect(throws: Transport.Failure.invalidNIP59Envelope) {
            _ = try Transport.openControl(
                ephemeral,
                context: runtimeContext(),
                recipientSigningKey: recipient,
                currentUnixSeconds: current
            )
        }

        let tagged = try customGiftWrap(
            canonicalEnvelope: bytes,
            sender: sender,
            recipient: recipient,
            additionalGiftWrapTags: [["x", "metadata"]],
            limits: permissiveLimits
        )
        #expect(throws: Transport.Failure.invalidGiftWrapTags) {
            _ = try Transport.openControl(
                tagged,
                context: runtimeContext(),
                recipientSigningKey: recipient,
                currentUnixSeconds: current
            )
        }

        let anonymousRecipient = try signingKey(17)
        let substitutedRecipient = try signingKey(18)
        let anonymousEnvelope = try anonymousEnvelope(
            senderSigningKey: sender,
            recipient: anonymousRecipient,
            payloadCount: 1
        )
        let anonymousBytes = try Alpha.CanonicalWireCodec
            .encodeAnonymousEnvelope(anonymousEnvelope)
        let recipientSubstitution = try customGiftWrap(
            canonicalEnvelope: anonymousBytes,
            sender: sender,
            recipient: substitutedRecipient
        )
        #expect(throws: Transport.Failure.recipientIdentityMismatch) {
            _ = try Transport.openAnonymous(
                recipientSubstitution,
                context: runtimeContext(),
                recipientSigningKey: substitutedRecipient,
                currentUnixSeconds: current
            )
        }
    }

    @Test("Reject rumor namespace, padding, sender, and timestamp substitution")
    func rejectInnerMappingSubstitution() throws {
        let sender = try signingKey(12)
        let recipient = try signingKey(13)
        let envelope = try controlEnvelope(
            eventSigningKey: sender,
            payloadCount: 1
        )
        let bytes = try Alpha.CanonicalWireCodec.encodeControlEnvelope(envelope)

        let wrongNamespace = try customGiftWrap(
            canonicalEnvelope: bytes,
            sender: sender,
            recipient: recipient,
            rumorTags: []
        )
        #expect(throws: Transport.Failure.invalidRumorTags) {
            _ = try Transport.openControl(
                wrongNamespace,
                context: runtimeContext(),
                recipientSigningKey: recipient,
                currentUnixSeconds: current
            )
        }

        let malformedPadding = try customGiftWrap(
            canonicalEnvelope: bytes,
            sender: sender,
            recipient: recipient,
            applicationContent: "g" + String(repeating: "0", count: 8_191)
        )
        #expect(
            throws: Transport.Failure.paddedPayload(
                .invalidLowercaseHexadecimal
            )
        ) {
            _ = try Transport.openControl(
                malformedPadding,
                context: runtimeContext(),
                recipientSigningKey: recipient,
                currentUnixSeconds: current
            )
        }

        let substitutedSender = try customGiftWrap(
            canonicalEnvelope: bytes,
            sender: signingKey(14),
            recipient: recipient
        )
        #expect(throws: Transport.Failure.senderIdentityMismatch) {
            _ = try Transport.openControl(
                substitutedSender,
                context: runtimeContext(),
                recipientSigningKey: recipient,
                currentUnixSeconds: current
            )
        }

        let oldTimestamp = try customGiftWrap(
            canonicalEnvelope: bytes,
            sender: sender,
            recipient: recipient,
            sealCreatedAt: phaseStart - 1
        )
        #expect(throws: Transport.Failure.invalidRumorTimestamp) {
            _ = try Transport.openControl(
                oldTimestamp,
                context: runtimeContext(),
                recipientSigningKey: recipient,
                currentUnixSeconds: current
            )
        }
    }

    @Test(
        "Mutate composite NIP-59 open parsers",
        .timeLimit(.minutes(1))
    )
    func mutateCompositeOpenParsers() throws {
        let limits = try Transport.codingLimits
        let controlSender = try signingKey(22)
        let controlRecipient = try signingKey(23)
        let anonymousSender = try signingKey(25)
        let anonymousRecipient = try signingKey(26)

        func makeGiftWrap(
            canonicalEnvelope: [UInt8],
            sender: OpalCrypto.Secp256k1.SigningKey,
            recipient: OpalCrypto.Secp256k1.SigningKey,
            wrapperScalarByte: UInt8,
            nonceByte: UInt8
        ) throws -> Nostr.Event {
            let rumor = try Nostr.UnsignedEvent(
                publicKey: sender.bip340VerificationKey,
                template: .init(
                    createdAt: current,
                    kind: Alpha.nip59RumorKind,
                    tags: [[
                        "d",
                        OpalFusion.Mosaic.TransportProfile
                            .nostrTorOpalMainnetAlpha.rawValue,
                    ]],
                    content: try OpalFusion.Mosaic.PaddedEnvelopeCodec
                        .encode(canonicalEnvelope),
                    limits: limits.event
                ),
                limits: limits.event
            )
            let seal = try Nostr.NIP59EnvelopeCodec.seal(
                rumor,
                createdAt: current - 2,
                senderSigningKey: sender,
                recipientPublicKey: recipient.bip340VerificationKey,
                nonce: .init(
                    rawRepresentation: Data(repeating: nonceByte, count: 32)
                ),
                auxiliaryRandomness: .init(
                    rawRepresentation: Data(
                        repeating: nonceByte &+ 1,
                        count: 32
                    )
                ),
                limits: limits
            )
            return try Nostr.NIP59EnvelopeCodec.wrap(
                seal,
                deliveryKind: .regular,
                createdAt: current - 1,
                wrapperSigningKey: signingKey(wrapperScalarByte),
                nonce: .init(
                    rawRepresentation: Data(
                        repeating: nonceByte &+ 2,
                        count: 32
                    )
                ),
                auxiliaryRandomness: .init(
                    rawRepresentation: Data(
                        repeating: nonceByte &+ 3,
                        count: 32
                    )
                ),
                limits: limits
            )
        }

        let controlGiftWrap = try makeGiftWrap(
            canonicalEnvelope: Alpha.CanonicalWireCodec
                .encodeControlEnvelope(
                    controlEnvelope(
                        eventSigningKey: controlSender,
                        payloadCount: 1
                    )
                ),
            sender: controlSender,
            recipient: controlRecipient,
            wrapperScalarByte: 24,
            nonceByte: 0xD6
        )
        let anonymousGiftWrap = try makeGiftWrap(
            canonicalEnvelope: Alpha.CanonicalWireCodec
                .encodeAnonymousEnvelope(
                    anonymousEnvelope(
                        senderSigningKey: anonymousSender,
                        recipient: anonymousRecipient,
                        payloadCount: 1
                    )
                ),
            sender: anonymousSender,
            recipient: anonymousRecipient,
            wrapperScalarByte: 27,
            nonceByte: 0xDA
        )
        let vectors = try [
            MosaicDeterministicParserMutationVector(
                name: "post-manifest control NIP-59 gift wrap",
                seedBytes: Array(Nostr.EventCodec.encode(
                    controlGiftWrap,
                    limits: limits.event
                ))
            ) { bytes in
                let giftWrap = try Nostr.EventCodec.decode(
                    Data(bytes),
                    limits: limits.event
                )
                guard case .control = try Transport.openControl(
                    giftWrap,
                    context: runtimeContext(),
                    recipientSigningKey: controlRecipient,
                    currentUnixSeconds: current
                ).storage else {
                    return false
                }
                return try Nostr.EventCodec.encode(
                    giftWrap,
                    limits: limits.event
                ) == Data(bytes)
            },
            MosaicDeterministicParserMutationVector(
                name: "post-manifest anonymous NIP-59 gift wrap",
                seedBytes: Array(Nostr.EventCodec.encode(
                    anonymousGiftWrap,
                    limits: limits.event
                ))
            ) { bytes in
                let giftWrap = try Nostr.EventCodec.decode(
                    Data(bytes),
                    limits: limits.event
                )
                guard case .anonymous = try Transport.openAnonymous(
                    giftWrap,
                    context: runtimeContext(),
                    recipientSigningKey: anonymousRecipient,
                    currentUnixSeconds: current
                ).storage else {
                    return false
                }
                return try Nostr.EventCodec.encode(
                    giftWrap,
                    limits: limits.event
                ) == Data(bytes)
            },
        ]

        try MosaicDeterministicParserMutationCampaign.validate(
            vectors,
            seed: 0xA54F_F53A_5F1D_36F1,
            seededMutationCount: 64
        )
    }

    private func assertFixedSizes(
        _ giftWrap: Nostr.Event,
        sender: OpalCrypto.Secp256k1.SigningKey,
        recipient: OpalCrypto.Secp256k1.SigningKey
    ) throws {
        let limits = try Transport.codingLimits
        let opened = try Nostr.NIP59EnvelopeCodec.open(
            giftWrap,
            expectedDeliveryKind: .regular,
            expectedRumorKind: Alpha.nip59RumorKind,
            recipientSigningKey: recipient,
            limits: limits
        )
        #expect(opened.senderPublicKey == sender.bip340VerificationKey)
        #expect(opened.rumor.template.content.utf8.count == 8_192)
        #expect(opened.rumorJSONByteCount == 8_438)
        #expect(opened.sealContentByteCount == 13_744)
        #expect(opened.sealJSONByteCount == 14_087)
        #expect(opened.giftWrapContentByteCount == 19_204)
        #expect(
            try Nostr.EventCodec.encode(giftWrap, limits: limits.event).count
                == 19_621
        )

        let relayLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: Alpha.nip59MaximumPublicationFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 1_024,
            event: limits.event
        )
        #expect(
            try Nostr.RelayMessageCodec.encode(
                .event(giftWrap),
                limits: relayLimits
            ).count == 19_631
        )
    }

    private func controlEnvelope(
        eventSigningKey: OpalCrypto.Secp256k1.SigningKey,
        payloadCount: Int,
        expiryUnixSeconds: UInt64? = nil
    ) throws -> Alpha.ControlEnvelope {
        let controlSigningKey = try signingKey(1)
        let sender = Attempt.ControlIdentity(
            validatedBytes: Array(
                controlSigningKey.bip340VerificationKey.rawRepresentation
            )
        )
        let eventIdentity = Array(
            eventSigningKey.bip340VerificationKey.rawRepresentation
        )
        let payload = [UInt8](repeating: 0xA1, count: payloadCount)
        let effectiveExpiry = expiryUnixSeconds ?? expiry
        let digest = try Alpha.ControlEnvelope.signingDigest(
            roundIdentifier: roundIdentifier,
            phase: .manifestAgreement,
            senderControlIdentity: sender,
            senderEventIdentity: eventIdentity,
            sequence: 0,
            payloadType: .aggregateReservation,
            expiryUnixSeconds: effectiveExpiry,
            payload: payload
        )
        let signature = try controlSigningKey.signBIP340(
            digest: .init(rawRepresentation: Data(digest)),
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0xA2, count: 32)
            )
        )
        return try .init(
            roundIdentifier: roundIdentifier,
            phase: .manifestAgreement,
            senderControlIdentity: sender,
            senderEventIdentity: eventIdentity,
            sequence: 0,
            payloadType: .aggregateReservation,
            expiryUnixSeconds: effectiveExpiry,
            controlSignature: Array(signature.rawRepresentation),
            payload: payload
        )
    }

    private func anonymousEnvelope(
        senderSigningKey: OpalCrypto.Secp256k1.SigningKey,
        recipient: OpalCrypto.Secp256k1.SigningKey,
        payloadCount: Int
    ) throws -> Alpha.AnonymousEnvelope {
        try .init(
            roundIdentifier: roundIdentifier,
            phase: .anonymousComponentSubmission,
            senderCommunicationPublicKey: Array(
                senderSigningKey.publicKey.compressedRepresentation
            ),
            recipientEventIdentity: Array(
                recipient.bip340VerificationKey.rawRepresentation
            ),
            sequence: 0,
            payloadType: .anonymousComponent,
            expiryUnixSeconds: expiry,
            payload: [UInt8](repeating: 0xB1, count: payloadCount)
        )
    }

    private func customGiftWrap(
        canonicalEnvelope: [UInt8],
        sender: OpalCrypto.Secp256k1.SigningKey,
        recipient: OpalCrypto.Secp256k1.SigningKey,
        deliveryKind: Nostr.NIP59EnvelopeCodec.DeliveryKind = .regular,
        rumorTags: [[String]]? = nil,
        additionalGiftWrapTags: [[String]] = [],
        applicationContent: String? = nil,
        rumorCreatedAt: UInt64? = nil,
        sealCreatedAt: UInt64? = nil,
        giftWrapCreatedAt: UInt64? = nil,
        limits: Nostr.NIP59EnvelopeCodec.CodingLimits? = nil
    ) throws -> Nostr.Event {
        let limits = try limits ?? Transport.codingLimits
        let content = try applicationContent
            ?? OpalFusion.Mosaic.PaddedEnvelopeCodec.encode(canonicalEnvelope)
        let rumor = try Nostr.UnsignedEvent(
            publicKey: sender.bip340VerificationKey,
            template: .init(
                createdAt: rumorCreatedAt ?? current,
                kind: Alpha.nip59RumorKind,
                tags: rumorTags ?? [[
                    "d",
                    OpalFusion.Mosaic.TransportProfile
                        .nostrTorOpalMainnetAlpha.rawValue,
                ]],
                content: content,
                limits: limits.event
            ),
            limits: limits.event
        )
        let seal = try Nostr.NIP59EnvelopeCodec.seal(
            rumor,
            createdAt: sealCreatedAt ?? current - 2,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: limits
        )
        return try Nostr.NIP59EnvelopeCodec.wrap(
            seal,
            deliveryKind: deliveryKind,
            createdAt: giftWrapCreatedAt ?? current - 1,
            additionalTags: additionalGiftWrapTags,
            limits: limits
        )
    }

    private func deterministicEncryptedEvent(
        plaintext: String,
        kind: UInt16,
        tags: [[String]],
        signingKey: OpalCrypto.Secp256k1.SigningKey,
        recipient: OpalCrypto.Secp256k1.SigningKey,
        nonceByte: UInt8,
        auxiliaryRandomnessByte: UInt8,
        createdAt: UInt64,
        maximumPlaintextByteCount: Int,
        limits: Nostr.NIP59EnvelopeCodec.CodingLimits
    ) throws -> Nostr.Event {
        let conversationKey = OpalCrypto.Nostr.NIP44.deriveConversationKey(
            signingKey: signingKey,
            publicKey: recipient.bip340VerificationKey
        )
        let payload = try OpalCrypto.Nostr.NIP44.encrypt(
            plaintext,
            conversationKey: conversationKey,
            nonce: .init(
                rawRepresentation: Data(repeating: nonceByte, count: 32)
            ),
            maximumPlaintextByteCount: maximumPlaintextByteCount
        )
        let template = try Nostr.EventTemplate(
            createdAt: createdAt,
            kind: kind,
            tags: tags,
            content: payload.encodedRepresentation,
            limits: limits.event
        )
        return try Nostr.EventSigner.sign(
            template,
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(
                    repeating: auxiliaryRandomnessByte,
                    count: 32
                )
            ),
            limits: limits.event
        )
    }

    private func recipientTag(
        _ recipient: OpalCrypto.Secp256k1.SigningKey
    ) -> [String] {
        ["p", hexadecimal(recipient.bip340VerificationKey.rawRepresentation)]
    }

    private func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private var permissiveLimits: Nostr.NIP59EnvelopeCodec.CodingLimits {
        get throws {
            let event = try Nostr.EventCodingLimits(
                maximumEventJSONByteCount: 20_000,
                maximumTagCount: 2,
                maximumTagElementCount: 2,
                maximumStringByteCount: 19_204
            )
            return try .init(
                event: event,
                maximumRumorJSONByteCount: 8_448,
                maximumSealJSONByteCount: 14_097
            )
        }
    }

    private func layerTimestamps() throws -> Transport.LayerTimestamps {
        try .init(
            phaseStartUnixSeconds: phaseStart,
            currentUnixSeconds: current,
            sealCreatedAt: current - 2,
            giftWrapCreatedAt: current - 1
        )
    }

    private func runtimeContext() -> Transport.RuntimeContext {
        .init(
            attemptIdentifier: .init(
                validatedBytes: [UInt8](repeating: 0xC1, count: 32)
            ),
            generationIdentifier: .init(
                opaqueBytes: [UInt8](repeating: 0xC2, count: 32)
            ),
            phaseStartUnixSeconds: phaseStart
        )
    }

    private func signingKey(
        _ scalarByte: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
    }

    private var roundIdentifier: [UInt8] {
        [UInt8](repeating: 0xD1, count: 32)
    }
}
