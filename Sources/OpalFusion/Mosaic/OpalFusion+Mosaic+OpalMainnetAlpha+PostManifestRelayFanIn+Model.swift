// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayFanIn+Model.swift

import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestRelayFanIn {
    typealias Driver = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRuntimeDriver
    typealias Ingress = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestTransportIngress
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias RelayEndpoint = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelayEndpoint
    typealias RelayRoute = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelayRoute
    typealias RelaySelectionValidation = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestRelaySelectionValidation
    typealias Transport = OpalFusion.Mosaic.OpalMainnetAlpha
        .PostManifestNIP59Transport

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
