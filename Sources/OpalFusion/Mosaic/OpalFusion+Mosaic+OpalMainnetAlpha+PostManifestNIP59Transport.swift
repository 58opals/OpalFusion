// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestNIP59Transport.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Frozen NIP-59 mapping for canonical post-manifest mainnet-alpha envelopes.
    ///
    /// The same signed regular gift wrap is replicated to all relays. Nostr timestamps
    /// are cover metadata and never replace the signed Mosaic expiry or phase state.
    enum PostManifestNIP59Transport {
        /// Opaque authenticated input accepted by the post-manifest runtime driver.
        struct AuthenticatedDelivery: Sendable, Equatable {
            enum Storage: Sendable, Equatable {
                case control(Ledger.ControlDelivery)
                case anonymous(Ledger.AnonymousDelivery)
            }

            let storage: Storage

            fileprivate init(storage: Storage) {
                self.storage = storage
            }
        }

        static var codingLimits: Nostr.NIP59EnvelopeCodec.CodingLimits {
            get throws {
                let event = try Nostr.EventCodingLimits(
                    maximumEventJSONByteCount:
                        OpalFusion.Mosaic.OpalMainnetAlpha
                            .nip59MaximumGiftWrapJSONByteCount,
                    maximumTagCount: 1,
                    maximumTagElementCount: 2,
                    maximumStringByteCount:
                        OpalFusion.Mosaic.OpalMainnetAlpha
                            .nip59GiftWrapContentByteCount
                )
                return try .init(
                    event: event,
                    maximumRumorJSONByteCount:
                        OpalFusion.Mosaic.OpalMainnetAlpha
                            .nip59MaximumRumorJSONByteCount,
                    maximumSealJSONByteCount:
                        OpalFusion.Mosaic.OpalMainnetAlpha
                            .nip59MaximumSealJSONByteCount
                )
            }
        }

        static func makeControlGiftWrap(
            _ envelope: ControlEnvelope,
            context: RuntimeContext,
            timestamps: LayerTimestamps,
            senderEventSigningKey: OpalCrypto.Secp256k1.SigningKey,
            recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            randomness: OutboundRandomness? = nil
        ) throws(Failure) -> Nostr.Event {
            guard timestamps.phaseStartUnixSeconds
                    == context.phaseStartUnixSeconds else {
                throw .invalidLayerTimestamps
            }
            guard Array(
                senderEventSigningKey.bip340VerificationKey.rawRepresentation
            ) == envelope.senderEventIdentity else {
                throw .senderIdentityMismatch
            }
            let bytes: [UInt8]
            do {
                bytes = try CanonicalWireCodec.encodeControlEnvelope(envelope)
            } catch {
                throw .invalidCanonicalEnvelope
            }
            return try makeGiftWrap(
                canonicalEnvelope: bytes,
                expiryUnixSeconds: envelope.expiryUnixSeconds,
                timestamps: timestamps,
                senderSigningKey: senderEventSigningKey,
                recipientPublicKey: recipientPublicKey,
                randomness: randomness
            )
        }

        static func makeAnonymousGiftWrap(
            _ envelope: AnonymousEnvelope,
            context: RuntimeContext,
            timestamps: LayerTimestamps,
            senderCommunicationSigningKey: OpalCrypto.Secp256k1.SigningKey,
            recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey
        ) throws(Failure) -> Nostr.Event {
            guard timestamps.phaseStartUnixSeconds
                    == context.phaseStartUnixSeconds else {
                throw .invalidLayerTimestamps
            }
            guard Array(
                senderCommunicationSigningKey.bip340VerificationKey
                    .rawRepresentation
            ) == Array(envelope.senderCommunicationPublicKey.dropFirst()) else {
                throw .senderIdentityMismatch
            }
            guard Array(recipientPublicKey.rawRepresentation)
                    == envelope.recipientEventIdentity else {
                throw .recipientIdentityMismatch
            }
            let bytes: [UInt8]
            do {
                bytes = try CanonicalWireCodec.encodeAnonymousEnvelope(envelope)
            } catch {
                throw .invalidCanonicalEnvelope
            }
            return try makeGiftWrap(
                canonicalEnvelope: bytes,
                expiryUnixSeconds: envelope.expiryUnixSeconds,
                timestamps: timestamps,
                senderSigningKey: senderCommunicationSigningKey,
                recipientPublicKey: recipientPublicKey
            )
        }

        static func openControl(
            _ giftWrap: Nostr.Event,
            context: RuntimeContext,
            recipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
            currentUnixSeconds: UInt64
        ) throws(Failure) -> AuthenticatedDelivery {
            let opened = try open(
                giftWrap,
                recipientSigningKey: recipientSigningKey
            )
            let bytes = try decodeApplicationContent(opened.rumor.template.content)
            let envelope: ControlEnvelope
            do {
                envelope = try CanonicalWireCodec.decodeControlEnvelope(
                    from: bytes
                )
            } catch {
                throw .invalidCanonicalEnvelope
            }
            do {
                try envelope.validateOuterEventIdentity(
                    Array(opened.senderPublicKey.rawRepresentation)
                )
            } catch {
                throw .senderIdentityMismatch
            }
            try validateRumorTimestamp(
                opened.rumor.template.createdAt,
                expiryUnixSeconds: envelope.expiryUnixSeconds,
                context: context,
                opened: opened
            )
            let delivery = Ledger.ControlDelivery(
                attemptIdentifier: context.attemptIdentifier,
                generationIdentifier: context.generationIdentifier,
                envelope: envelope,
                authenticatedOuterEventIdentity:
                    Array(opened.senderPublicKey.rawRepresentation),
                currentUnixSeconds: currentUnixSeconds
            )
            return .init(storage: .control(delivery))
        }

        static func openAnonymous(
            _ giftWrap: Nostr.Event,
            context: RuntimeContext,
            recipientSigningKey: OpalCrypto.Secp256k1.SigningKey,
            currentUnixSeconds: UInt64
        ) throws(Failure) -> AuthenticatedDelivery {
            let opened = try open(
                giftWrap,
                recipientSigningKey: recipientSigningKey
            )
            let bytes = try decodeApplicationContent(opened.rumor.template.content)
            let envelope: AnonymousEnvelope
            do {
                envelope = try CanonicalWireCodec.decodeAnonymousEnvelope(
                    from: bytes
                )
            } catch {
                throw .invalidCanonicalEnvelope
            }
            guard Array(opened.recipientPublicKey.rawRepresentation)
                    == envelope.recipientEventIdentity else {
                throw .recipientIdentityMismatch
            }
            do {
                try envelope.validateOuterEventIdentity(
                    Array(opened.senderPublicKey.rawRepresentation)
                )
            } catch {
                throw .senderIdentityMismatch
            }
            try validateRumorTimestamp(
                opened.rumor.template.createdAt,
                expiryUnixSeconds: envelope.expiryUnixSeconds,
                context: context,
                opened: opened
            )
            let messageIdentifier: OpalFusion.Mosaic.RuntimeSession
                .MessageIdentifier
            do {
                messageIdentifier = try .init(
                    bytes: Array(opened.giftWrapIdentifier.rawRepresentation)
                )
            } catch {
                throw .invalidRuntimeMessageIdentifier
            }
            let delivery = Ledger.AnonymousDelivery(
                attemptIdentifier: context.attemptIdentifier,
                generationIdentifier: context.generationIdentifier,
                envelope: envelope,
                authenticatedOuterEventIdentity:
                    Array(opened.senderPublicKey.rawRepresentation),
                authenticatedRecipientEventIdentity: Array(
                    opened.recipientPublicKey.rawRepresentation
                ),
                authenticatedMessageIdentifier: messageIdentifier,
                currentUnixSeconds: currentUnixSeconds
            )
            return .init(storage: .anonymous(delivery))
        }

        static func relayFilter(
            recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey
        ) throws(Failure) -> Nostr.RelayFilter {
            do {
                return try .init(
                    kinds: [Nostr.NIP59EnvelopeCodec.DeliveryKind.regular.rawValue],
                    recipientPublicKeys: [recipientPublicKey]
                )
            } catch {
                throw .envelopeConstructionFailed
            }
        }

        /// Extracts the sole canonical recipient identity before decryption authority is selected.
        static func recipientEventIdentity(
            in giftWrap: Nostr.Event
        ) throws(Failure) -> Data {
            guard giftWrap.template.tags.count == 1,
                  giftWrap.template.tags[0].count == 2,
                  giftWrap.template.tags[0][0] == "p" else {
                throw .invalidGiftWrapTags
            }
            do {
                let rawRepresentation = try Nostr.EventCodec.decodeHexadecimal(
                    giftWrap.template.tags[0][1],
                    field: "p"
                )
                return try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: rawRepresentation
                ).rawRepresentation
            } catch {
                throw .invalidGiftWrapTags
            }
        }

        private static func makeGiftWrap(
            canonicalEnvelope: [UInt8],
            expiryUnixSeconds: UInt64,
            timestamps: LayerTimestamps,
            senderSigningKey: OpalCrypto.Secp256k1.SigningKey,
            recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            randomness: OutboundRandomness? = nil
        ) throws(Failure) -> Nostr.Event {
            guard timestamps.rumorCreatedAt <= expiryUnixSeconds else {
                throw .invalidRumorTimestamp
            }
            let content: String
            do {
                content = try OpalFusion.Mosaic.PaddedEnvelopeCodec.encode(
                    canonicalEnvelope
                )
            } catch let error as OpalFusion.Mosaic.PaddedEnvelopeCodec.CodingError {
                throw .paddedPayload(error)
            } catch {
                throw .envelopeConstructionFailed
            }
            guard content.utf8.count
                == OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59ApplicationContentByteCount else {
                throw .envelopeConstructionFailed
            }

            do {
                let limits = try codingLimits
                let template = try Nostr.EventTemplate(
                    createdAt: timestamps.rumorCreatedAt,
                    kind: OpalFusion.Mosaic.OpalMainnetAlpha.nip59RumorKind,
                    tags: applicationRumorTags,
                    content: content,
                    limits: limits.event
                )
                let rumor = try Nostr.UnsignedEvent(
                    publicKey: senderSigningKey.bip340VerificationKey,
                    template: template,
                    limits: limits.event
                )
                let seal: Nostr.NIP59EnvelopeCodec.SealedRumor
                let giftWrap: Nostr.Event
                if let randomness {
                    seal = try Nostr.NIP59EnvelopeCodec.seal(
                        rumor,
                        createdAt: timestamps.sealCreatedAt,
                        senderSigningKey: senderSigningKey,
                        recipientPublicKey: recipientPublicKey,
                        nonce: randomness.sealNonce,
                        auxiliaryRandomness:
                            randomness.sealAuxiliaryRandomness,
                        limits: limits
                    )
                    giftWrap = try Nostr.NIP59EnvelopeCodec.wrap(
                        seal,
                        deliveryKind: .regular,
                        createdAt: timestamps.giftWrapCreatedAt,
                        wrapperSigningKey: randomness.wrapperSigningKey,
                        nonce: randomness.wrapperNonce,
                        auxiliaryRandomness:
                            randomness.wrapperAuxiliaryRandomness,
                        limits: limits
                    )
                } else {
                    seal = try Nostr.NIP59EnvelopeCodec.seal(
                        rumor,
                        createdAt: timestamps.sealCreatedAt,
                        senderSigningKey: senderSigningKey,
                        recipientPublicKey: recipientPublicKey,
                        limits: limits
                    )
                    giftWrap = try Nostr.NIP59EnvelopeCodec.wrap(
                        seal,
                        deliveryKind: .regular,
                        createdAt: timestamps.giftWrapCreatedAt,
                        limits: limits
                    )
                }
                try validateFixedOutboundSizes(
                    seal: seal.event,
                    giftWrap: giftWrap,
                    limits: limits
                )
                return giftWrap
            } catch let failure as Failure {
                throw failure
            } catch {
                throw .envelopeConstructionFailed
            }
        }

        private static func open(
            _ giftWrap: Nostr.Event,
            recipientSigningKey: OpalCrypto.Secp256k1.SigningKey
        ) throws(Failure) -> Nostr.NIP59EnvelopeCodec.AuthenticatedRumor {
            let expectedTags = [recipientTag(
                recipientSigningKey.bip340VerificationKey
            )]
            guard giftWrap.template.tags == expectedTags else {
                throw .invalidGiftWrapTags
            }
            let opened: Nostr.NIP59EnvelopeCodec.AuthenticatedRumor
            do {
                opened = try Nostr.NIP59EnvelopeCodec.open(
                    giftWrap,
                    expectedDeliveryKind: .regular,
                    expectedRumorKind:
                        OpalFusion.Mosaic.OpalMainnetAlpha.nip59RumorKind,
                    recipientSigningKey: recipientSigningKey,
                    limits: try codingLimits
                )
            } catch {
                throw .invalidNIP59Envelope
            }
            guard opened.rumor.template.tags == applicationRumorTags else {
                throw .invalidRumorTags
            }
            guard opened.rumorJSONByteCount
                    <= OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59MaximumRumorJSONByteCount,
                  opened.sealContentByteCount
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59SealContentByteCount,
                  opened.sealJSONByteCount
                    <= OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59MaximumSealJSONByteCount,
                  opened.giftWrapContentByteCount
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59GiftWrapContentByteCount else {
                throw .invalidNIP59Envelope
            }
            return opened
        }

        private static func decodeApplicationContent(
            _ content: String
        ) throws(Failure) -> [UInt8] {
            do {
                return try OpalFusion.Mosaic.PaddedEnvelopeCodec.decode(content)
            } catch let error as OpalFusion.Mosaic.PaddedEnvelopeCodec.CodingError {
                throw .paddedPayload(error)
            } catch {
                throw .invalidCanonicalEnvelope
            }
        }

        private static func validateRumorTimestamp(
            _ rumorCreatedAt: UInt64,
            expiryUnixSeconds: UInt64,
            context: RuntimeContext,
            opened: Nostr.NIP59EnvelopeCodec.AuthenticatedRumor
        ) throws(Failure) {
            guard context.phaseStartUnixSeconds < rumorCreatedAt,
                  rumorCreatedAt <= expiryUnixSeconds,
                  opened.sealCreatedAt >= context.phaseStartUnixSeconds,
                  opened.sealCreatedAt < rumorCreatedAt,
                  opened.giftWrapCreatedAt >= context.phaseStartUnixSeconds,
                  opened.giftWrapCreatedAt < rumorCreatedAt else {
                throw .invalidRumorTimestamp
            }
        }

        private static func validateFixedOutboundSizes(
            seal: Nostr.Event,
            giftWrap: Nostr.Event,
            limits: Nostr.NIP59EnvelopeCodec.CodingLimits
        ) throws {
            guard seal.template.content.utf8.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59SealContentByteCount,
                  giftWrap.template.content.utf8.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59GiftWrapContentByteCount,
                  try Nostr.EventCodec.encode(
                    giftWrap,
                    limits: limits.event
                  ).count <= OpalFusion.Mosaic.OpalMainnetAlpha
                    .nip59MaximumGiftWrapJSONByteCount else {
                throw Failure.envelopeConstructionFailed
            }
        }

        private static var applicationRumorTags: [[String]] {
            [["d", OpalFusion.Mosaic.TransportProfile
                .nostrTorOpalMainnetAlpha.rawValue]]
        }

        private static func recipientTag(
            _ publicKey: OpalCrypto.Signature.BIP340.VerificationKey
        ) -> [String] {
            ["p", Nostr.EventCodec.hexadecimal(publicKey.rawRepresentation)]
        }
    }
}
