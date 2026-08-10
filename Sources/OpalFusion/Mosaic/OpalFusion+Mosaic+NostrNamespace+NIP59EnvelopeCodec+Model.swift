// OpalFusion+Mosaic+NostrNamespace+NIP59EnvelopeCodec+Model.swift

import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace.NIP59EnvelopeCodec {
    /// The two delivery forms assigned by NIP-59.
    enum DeliveryKind: UInt16, CaseIterable, Sendable {
        /// Regular gift wrap. Relays may store it, but storage is not guaranteed.
        case regular = 1_059

        /// Ephemeral gift wrap. Conforming relays must not store it.
        case ephemeral = 21_059
    }

    /// Caller-owned allocation bounds; these are not Mosaic wire constants.
    struct CodingLimits: Sendable, Equatable {
        let event: OpalFusion.Mosaic.NostrNamespace.EventCodingLimits
        let maximumRumorJSONByteCount: Int
        let maximumSealJSONByteCount: Int

        init(
            event: OpalFusion.Mosaic.NostrNamespace.EventCodingLimits,
            maximumRumorJSONByteCount: Int,
            maximumSealJSONByteCount: Int
        ) throws {
            guard maximumRumorJSONByteCount > 0,
                  maximumSealJSONByteCount > 0,
                  maximumRumorJSONByteCount <= event.maximumEventJSONByteCount,
                  maximumSealJSONByteCount <= event.maximumEventJSONByteCount else {
                throw Error.invalidResourceLimit
            }
            self.event = event
            self.maximumRumorJSONByteCount = maximumRumorJSONByteCount
            self.maximumSealJSONByteCount = maximumSealJSONByteCount
        }
    }

    /// A rumor authenticated by its enclosing seal and decrypted for one recipient.
    ///
    /// All three identifiers are retained so each Mosaic transport profile can
    /// explicitly choose its replay identifier rather than inheriting one here.
    struct AuthenticatedRumor: Sendable, Equatable {
        let rumor: OpalFusion.Mosaic.NostrNamespace.UnsignedEvent
        let recipientPublicKey: OpalCrypto.Signature.BIP340.VerificationKey
        let sealIdentifier: OpalCrypto.Signature.Digest
        let giftWrapIdentifier: OpalCrypto.Signature.Digest
        let sealCreatedAt: UInt64
        let giftWrapCreatedAt: UInt64
        let rumorJSONByteCount: Int
        let sealContentByteCount: Int
        let sealJSONByteCount: Int
        let giftWrapContentByteCount: Int
        let deliveryKind: DeliveryKind

        var senderPublicKey: OpalCrypto.Signature.BIP340.VerificationKey {
            rumor.publicKey
        }
    }

    enum Error: Swift.Error, Sendable, Equatable {
        case invalidResourceLimit
        case rumorJSONByteCountExceedsMaximum(maximum: Int, actual: Int)
        case sealJSONByteCountExceedsMaximum(maximum: Int, actual: Int)
        case unexpectedGiftWrapKind(expected: UInt16, actual: UInt16)
        case invalidGiftWrapTags
        case invalidSealKind(actual: UInt16)
        case invalidSealTags
        case wrapperIdentityCollision
        case rumorAuthorMismatch
        case unexpectedRumorKind(expected: UInt16, actual: UInt16)
    }
}
