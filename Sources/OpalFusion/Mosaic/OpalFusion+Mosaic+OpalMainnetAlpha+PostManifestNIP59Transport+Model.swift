// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestNIP59Transport+Model.swift

import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestNIP59Transport {
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Ledger = OpalFusion.Mosaic.OpalMainnetAlpha.AdmissionLedger
    typealias Driver = OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRuntimeDriver

    enum Channel: Sendable, Equatable {
        case control
        case anonymous
    }

    /// Exact recipient decryption authority for one post-manifest mailbox.
    struct RecipientCapability: Sendable {
        let channel: Channel
        let signingKey: OpalCrypto.Secp256k1.SigningKey

        init(
            channel: Channel,
            signingKey: OpalCrypto.Secp256k1.SigningKey
        ) {
            self.channel = channel
            self.signingKey = signingKey
        }
    }

    /// NIP-59 cover timestamps bounded by the signed manifest phase start.
    struct LayerTimestamps: Sendable, Equatable {
        let phaseStartUnixSeconds: UInt64
        let rumorCreatedAt: UInt64
        let sealCreatedAt: UInt64
        let giftWrapCreatedAt: UInt64

        init(
            phaseStartUnixSeconds: UInt64,
            currentUnixSeconds: UInt64,
            sealCreatedAt: UInt64,
            giftWrapCreatedAt: UInt64
        ) throws(Failure) {
            guard phaseStartUnixSeconds < currentUnixSeconds,
                  sealCreatedAt >= phaseStartUnixSeconds,
                  sealCreatedAt < currentUnixSeconds,
                  giftWrapCreatedAt >= phaseStartUnixSeconds,
                  giftWrapCreatedAt < currentUnixSeconds else {
                throw .invalidLayerTimestamps
            }
            self.phaseStartUnixSeconds = phaseStartUnixSeconds
            self.rumorCreatedAt = currentUnixSeconds
            self.sealCreatedAt = sealCreatedAt
            self.giftWrapCreatedAt = giftWrapCreatedAt
        }
    }

    struct RuntimeContext: Sendable, Equatable {
        let attemptIdentifier: Ledger.AttemptIdentifier
        let generationIdentifier: Ledger.GenerationIdentifier
        let phaseStartUnixSeconds: UInt64
    }

    enum Failure: Error, Sendable, Equatable {
        case invalidLayerTimestamps
        case invalidGiftWrapTags
        case invalidRumorTags
        case invalidRumorTimestamp
        case senderIdentityMismatch
        case recipientIdentityMismatch
        case paddedPayload(OpalFusion.Mosaic.PaddedEnvelopeCodec.CodingError)
        case invalidCanonicalEnvelope
        case invalidNIP59Envelope
        case envelopeConstructionFailed
        case invalidRuntimeMessageIdentifier
    }
}
