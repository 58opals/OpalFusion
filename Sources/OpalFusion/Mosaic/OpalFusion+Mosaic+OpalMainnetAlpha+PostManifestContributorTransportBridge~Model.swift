// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestContributorTransportBridge~Model.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestContributorTransportBridge {
    typealias Coordinator = OpalFusion.Mosaic.OpalMainnetAlpha
        .ReservationCoordinator
    typealias Driver = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRuntimeDriver
    typealias ControlBridge = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestControlPublicationBridge
    typealias ControlPublisher = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestControlBatchPublisher
    typealias AnonymousBridge = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestAnonymousPublicationBridge
    typealias AnonymousPublisher = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestAnonymousBatchPublisher
    typealias AttemptTransportOwner = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestAttemptTransportOwner
    typealias PublicationJournal = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelayPublicationJournal
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace

    enum Publication: Sendable, Equatable {
        case playerCommit
        case anonymousComponents
        case preSignAcknowledgement
        case localBCHSignatures

        var next: Self? {
            switch self {
            case .playerCommit:
                .anonymousComponents
            case .anonymousComponents:
                .preSignAcknowledgement
            case .preSignAcknowledgement:
                .localBCHSignatures
            case .localBCHSignatures:
                nil
            }
        }
    }

    struct Dependencies: Sendable {
        /// Supplies the caller-owned expiry for one already-authorized publication.
        ///
        /// This seam deliberately does not derive a timing policy from the signed manifest.
        let makeExpiryUnixSeconds: @Sendable (Publication) throws -> UInt64
        let makeControlLayerTimestamps: @Sendable (
            ControlBridge.TimestampRequest
        ) throws -> Transport.LayerTimestamps
        let makeAnonymousLayerTimestamps: @Sendable (
            AnonymousBridge.TimestampRequest
        ) throws -> Transport.LayerTimestamps
        let makeControlSignatureAuxiliaryRandomness: @Sendable () throws
            -> OpalCrypto.Signature.BIP340.AuxiliaryRandomness
        let attemptTransportOwner: AttemptTransportOwner
        let publicationJournal: PublicationJournal
        let awaitAnonymousPublicationPermit:
            AnonymousPublisher.PublicationPermitProvider

        init(
            makeExpiryUnixSeconds: @escaping @Sendable (
                Publication
            ) throws -> UInt64,
            makeControlLayerTimestamps: @escaping @Sendable (
                ControlBridge.TimestampRequest
            ) throws -> Transport.LayerTimestamps,
            makeAnonymousLayerTimestamps: @escaping @Sendable (
                AnonymousBridge.TimestampRequest
            ) throws -> Transport.LayerTimestamps,
            makeControlSignatureAuxiliaryRandomness: @escaping @Sendable () throws
                -> OpalCrypto.Signature.BIP340.AuxiliaryRandomness = {
                    try .init(
                        rawRepresentation: OpalCrypto.SecureRandom.makeBytes(
                            count: 32
                        )
                    )
            },
            attemptTransportOwner: AttemptTransportOwner,
            publicationJournal: PublicationJournal,
            awaitAnonymousPublicationPermit: @escaping
                AnonymousPublisher.PublicationPermitProvider
        ) {
            self.makeExpiryUnixSeconds = makeExpiryUnixSeconds
            self.makeControlLayerTimestamps = makeControlLayerTimestamps
            self.makeAnonymousLayerTimestamps = makeAnonymousLayerTimestamps
            self.makeControlSignatureAuxiliaryRandomness =
                makeControlSignatureAuxiliaryRandomness
            self.attemptTransportOwner = attemptTransportOwner
            self.publicationJournal = publicationJournal
            self.awaitAnonymousPublicationPermit =
                awaitAnonymousPublicationPermit
        }

        var provideControlRoutes: ControlPublisher.RouteProvider {
            attemptTransportOwner.controlRouteProvider
        }

        var provideAnonymousRoutes:
            AnonymousPublisher.PurposefulRouteProvider {
            attemptTransportOwner.anonymousRouteProvider
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case invalidContext(ControlBridge.Context.ValidationError)
        case localPeerIsNotContributor
        case attemptTransportOwnerMismatch
        case controlPublisher(ControlPublisher.InitializationError)
        case controlBridge(ControlBridge.InitializationError)
    }

    enum State: Sendable, Equatable {
        case awaitingMaterial
        case preparingMaterial
        case ready(Publication)
        case publishing(Publication)
        case draining(Failure)
        case completed
        case terminal(Failure)
    }

    enum Failure: Error, Sendable, Equatable {
        case materialConstructionFailed
        case materialBindingFailed
        case invalidPublicationOrder
        case concurrentOperation
        case expiryUnavailable(Publication)
        case publicationFailed(Publication)
        case cancelled
        case inputAfterTermination
    }
}
