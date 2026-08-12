// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayFanIn+Model.swift

import OpalCrypto
import Synchronization

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRelayFanIn {
    typealias Driver = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRuntimeDriver
    typealias Ingress = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestTransportIngress
    typealias AttemptTransportOwner = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestAttemptTransportOwner
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias RelayEndpoint = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelayEndpoint
    typealias RelayRoute = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelayRoute
    typealias RelaySelectionValidation = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelaySelectionValidation
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport

    /// Opaque attempt facts that prevent a provisioned mailbox group from crossing runtimes.
    final class AttemptBinding: Sendable {
        private struct Facts: Sendable, Equatable {
            let attemptIdentifier: Driver.Session.AttemptIdentifier
            let generationIdentifier: Driver.Session.GenerationIdentifier
            let materialIdentifier: Driver.Session.MaterialIdentifier
            let localControlIdentity: Driver.Session.ControlIdentity
            let manifestCore: OpalFusion.Mosaic.OpalMainnetAlpha
                .RoundManifestCore
        }

        private let facts: Facts
        private let isClaimed = Mutex(false)

        init(bootstrap: Driver.Bootstrap) {
            facts = .init(
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                materialIdentifier: bootstrap.materialIdentifier,
                localControlIdentity: bootstrap.localControlIdentity,
                manifestCore: bootstrap.proposalValidation.core
            )
        }

        func matches(_ bootstrap: Driver.Bootstrap) -> Bool {
            facts == .init(
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                materialIdentifier: bootstrap.materialIdentifier,
                localControlIdentity: bootstrap.localControlIdentity,
                manifestCore: bootstrap.proposalValidation.core
            )
        }

        func claim() -> Bool {
            isClaimed.withLock {
                guard !$0 else { return false }
                $0 = true
                return true
            }
        }
    }

    /// One externally provisioned recipient mailbox and its isolated three-route subscription set.
    ///
    /// The caller remains responsible for recipient allocation, endpoint-to-capability binding,
    /// and Tor circuit isolation. The fan-in validates the entire supplied collection before opening any
    /// route and then feeds every group into one shared runtime authority.
    struct RecipientRouteGroup: Sendable {
        private let attemptBinding: AttemptBinding
        let recipient: Transport.RecipientCapability
        let routes: [RelayRoute]
        let subscriptionIdentifiers: [
            RelayEndpoint: Nostr.SubscriptionIdentifier
        ]

        init(
            attemptBinding: AttemptBinding,
            recipient: Transport.RecipientCapability,
            routes: [RelayRoute],
            subscriptionIdentifiers: [
                RelayEndpoint: Nostr.SubscriptionIdentifier
            ]
        ) {
            self.attemptBinding = attemptBinding
            self.recipient = recipient
            self.routes = routes
            self.subscriptionIdentifiers = subscriptionIdentifiers
        }

        func isBound(to bootstrap: Driver.Bootstrap) -> Bool {
            attemptBinding.matches(bootstrap)
        }

        func claimAttemptBinding() -> Bool {
            attemptBinding.claim()
        }
    }

    struct Dependencies: Sendable {
        /// Observes one completed ingress decision inline without controlling fan-in lifecycle.
        ///
        /// The observer must return immediately, perform no blocking work, and must not attempt
        /// to re-enter this fan-in. It cannot alter admission or terminal disposition.
        let submissionObserver: @Sendable (
            OpalCrypto.Signature.Digest,
            Ingress.Decision
        ) -> Void

        init(
            submissionObserver: @escaping @Sendable (
                OpalCrypto.Signature.Digest,
                Ingress.Decision
            ) -> Void = { _, _ in }
        ) {
            self.submissionObserver = submissionObserver
        }
    }

    enum InitializationError: Error, Sendable, Equatable {
        case invalidRecipientGroupCount(actual: Int)
        case invalidRecipientSet
        case invalidRecipientChannels
        case recipientAttemptBindingMismatch
        case invalidRelayCount(actual: Int)
        case duplicateRelay(RelayEndpoint)
        case duplicateConnection
        case relaySelectionManifestMismatch
        case relaySelectionMismatch
        case invalidSubscriptionCount(actual: Int)
        case subscriptionSetMismatch
        case duplicateSubscriptionIdentifier
        case incompatibleCodingLimits
        case invalidEventBufferLimit
        case invalidSubscription
        case runtimeAuthorizationMismatch
        case runtimeAuthorizationAlreadyUsed
        case ingress(Ingress.InitializationError)
    }

    enum Failure: Error, Sendable, Equatable {
        case alreadyUsed
        case sourceFailed
        case runtimeTerminated
        case cancelled
    }

    enum State: Sendable, Equatable {
        case idle
        case starting
        case running
        case stopping
        case terminal(Termination)
    }

    enum Termination: Sendable, Equatable {
        case runtime(Driver.State)
        case failed(Failure)
        case stopped
    }
}
