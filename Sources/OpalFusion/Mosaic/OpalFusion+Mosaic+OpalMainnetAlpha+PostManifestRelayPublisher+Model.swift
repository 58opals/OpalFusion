// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublisher+Model.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRelayPublisher {
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias RelayEndpoint = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelayEndpoint

    /// A signed regular gift wrap with the frozen alpha.5 outer publication shape.
    struct GiftWrap: Sendable, Equatable {
        let event: Nostr.Event

        init(validating event: Nostr.Event) throws(Failure) {
            let template = event.template
            guard template.kind
                    == Nostr.NIP59EnvelopeCodec.DeliveryKind.regular.rawValue,
                  template.tags.count == 1,
                  template.tags[0].count == 2,
                  template.tags[0][0] == "p",
                  template.content.utf8.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha
                        .nip59GiftWrapContentByteCount else {
                throw .invalidGiftWrap
            }
            do {
                let recipient = try OpalCrypto.Signature.BIP340.VerificationKey(
                    rawRepresentation: Nostr.EventCodec.decodeHexadecimal(
                        template.tags[0][1],
                        field: "p"
                    )
                )
                guard recipient != event.publicKey else {
                    throw Failure.invalidGiftWrap
                }
                let limits = try OpalFusion.Mosaic.OpalMainnetAlpha
                    .PostManifestNIP59Transport.codingLimits
                _ = try OpalCrypto.Nostr.NIP44.Payload(
                    encodedRepresentation: template.content,
                    maximumEncodedPayloadByteCount:
                        OpalFusion.Mosaic.OpalMainnetAlpha
                            .nip59GiftWrapContentByteCount
                )
                let encoded = try Nostr.EventCodec.encode(
                    event,
                    limits: limits.event
                )
                guard encoded.count
                        <= OpalFusion.Mosaic.OpalMainnetAlpha
                            .nip59MaximumGiftWrapJSONByteCount else {
                    throw Failure.invalidGiftWrap
                }
            } catch {
                throw .invalidGiftWrap
            }
            self.event = event
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case invalidRelayCount(actual: Int)
        case duplicateRelay(RelayEndpoint)
        case duplicateConnection
        case relaySelectionMismatch
        case incompatibleCodingLimits
        case invalidOutputBufferLimit
    }

    enum Failure: Error, Sendable, Equatable {
        case invalidGiftWrap
        case alreadyUsed
        case publicationRejected
        case cancelled
    }

    enum State: Sendable, Equatable {
        case idle
        case publishing(OpalCrypto.Signature.Digest)
        case stopping
        case terminal(Termination)
    }

    enum Termination: Sendable, Equatable {
        case accepted(OpalCrypto.Signature.Digest)
        case failed(Failure)
        case stopped
    }
}
