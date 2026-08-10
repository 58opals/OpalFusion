// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayPublisher+Model.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRelayPublisher {
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias RelayEndpoint = OpalFusion.Mosaic.RelayPublicationTracker.Endpoint

    /// One externally supplied opaque relay and its already Tor-routed connection.
    struct Route: Sendable {
        let endpoint: RelayEndpoint
        let connection: any OpalFusion.Mosaic.TorWebSocketConnectioning

        init(
            endpoint: RelayEndpoint,
            connection: any OpalFusion.Mosaic.TorWebSocketConnectioning
        ) {
            self.endpoint = endpoint
            self.connection = connection
        }
    }

    /// An injected authority that binds opaque relay endpoint identifiers to one manifest.
    ///
    /// Endpoint parsing, canonicalization, provisioning, and operator-independence checks remain
    /// outside this transport slice. The validator must establish that the exact three opaque
    /// endpoint identifiers are the selection committed by `manifestRelaySetDigest`. The route
    /// owner separately binds each validated identifier to its injected Tor capability.
    protocol RelaySelectionValidating: Sendable {
        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [RelayEndpoint]
        ) throws
    }

    /// Seals validated manifest relay endpoint identifiers for one publisher construction.
    struct RelaySelectionValidation: Sendable, Equatable {
        enum ValidationError: Error, Sendable, Equatable {
            case invalidRelaySetDigest(actual: Int)
            case invalidRelayCount(actual: Int)
            case duplicateRelay(RelayEndpoint)
            case rejected
        }

        let manifestRelaySetDigest: [UInt8]
        let endpoints: [RelayEndpoint]

        init(
            manifestRelaySetDigest: [UInt8],
            endpoints: [RelayEndpoint],
            using validator: some RelaySelectionValidating
        ) throws(ValidationError) {
            guard manifestRelaySetDigest.count == 32 else {
                throw .invalidRelaySetDigest(
                    actual: manifestRelaySetDigest.count
                )
            }
            guard endpoints.count
                    == OpalFusion.Mosaic.OpalMainnetAlpha.relayCount else {
                throw .invalidRelayCount(actual: endpoints.count)
            }
            var uniqueEndpoints: Set<RelayEndpoint> = []
            for endpoint in endpoints {
                guard uniqueEndpoints.insert(endpoint).inserted else {
                    throw .duplicateRelay(endpoint)
                }
            }
            do {
                try validator.validateRelaySelection(
                    manifestRelaySetDigest: manifestRelaySetDigest,
                    endpoints: endpoints
                )
            } catch {
                throw .rejected
            }
            self.manifestRelaySetDigest = Array(manifestRelaySetDigest)
            self.endpoints = endpoints
        }
    }

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
