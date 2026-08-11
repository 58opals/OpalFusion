// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestAnonymousPublicationBridge+Model.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha
    .PostManifestAnonymousPublicationBridge
{
    typealias Context = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestControlPublicationBridge.Context
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport
    typealias ComponentValidation = OpalFusion.Mosaic.OpalMainnetAlpha
        .ReservationCoordinator.AnonymousComponentPublicationValidation
    typealias BCHSignatureValidation = OpalFusion.Mosaic.OpalMainnetAlpha
        .ReservationCoordinator.AnonymousBCHSignaturePublicationValidation
    typealias MaterialBinding = OpalFusion.Mosaic.OpalMainnetAlpha
        .ReservationCoordinator.AnonymousMaterialBinding

    enum PublicationKind: Sendable, Equatable {
        case components
        case bchSignatures
    }

    struct RecipientGiftWrap: Sendable, Equatable {
        let recipientEventIdentity: Data
        let giftWrap: OpalFusion.Mosaic.OpalMainnetAlpha
            .PostManifestRelayPublisher.GiftWrap

        init(
            recipientEventIdentity: Data,
            giftWrap: OpalFusion.Mosaic.OpalMainnetAlpha
                .PostManifestRelayPublisher.GiftWrap
        ) {
            self.recipientEventIdentity = recipientEventIdentity
            self.giftWrap = giftWrap
        }
    }

    /// One purpose-specific anonymous publication handoff without contributor or slot labels.
    struct GiftWrapBatch: Sendable, Equatable {
        let recipients: [RecipientGiftWrap]

        init(recipients: [RecipientGiftWrap]) {
            self.recipients = recipients
        }
    }

    struct TimestampRequest: Sendable, Equatable {
        let recipientEventIdentity: Data
        let phase: OpalFusion.Mosaic.Attempt.Phase
        let sequence: UInt64
        let expiryUnixSeconds: UInt64
    }

    struct Dependencies: Sendable {
        /// Supplies caller-owned cover timestamps without defining a timing policy.
        let makeLayerTimestamps: @Sendable (
            TimestampRequest
        ) throws -> Transport.LayerTimestamps

        /// Hands one complete purpose-specific batch to the transport owner.
        ///
        /// The operation must return after transport acknowledgement without awaiting semantic
        /// loopback admission or synchronously re-entering this bridge.
        let handoffGiftWrapBatch: @Sendable (
            GiftWrapBatch
        ) async throws -> Void

        init(
            makeLayerTimestamps: @escaping @Sendable (
                TimestampRequest
            ) throws -> Transport.LayerTimestamps,
            handoffGiftWrapBatch: @escaping @Sendable (
                GiftWrapBatch
            ) async throws -> Void
        ) {
            self.makeLayerTimestamps = makeLayerTimestamps
            self.handoffGiftWrapBatch = handoffGiftWrapBatch
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case localPeerIsNotContributor
        case localMaterialMismatch
    }

    enum State: Sendable, Equatable {
        case readyForComponents
        case publishing(PublicationKind)
        case componentsPublished
        case completed
        case terminal(Failure)
    }

    enum Failure: Error, Sendable, Equatable {
        case invalidPublication
        case invalidOrder
        case giftWrapConstructionFailed
        case handoffFailed
        case concurrentPublication
        case cancelled
        case inputAfterTermination
    }
}
