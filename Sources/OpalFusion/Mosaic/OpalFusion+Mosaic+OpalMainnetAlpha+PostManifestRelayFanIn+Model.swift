// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRelayFanIn+Model.swift

import OpalCrypto

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

    /// One externally provisioned recipient mailbox and its isolated three-route subscription set.
    ///
    /// The caller remains responsible for recipient allocation, endpoint-to-capability binding,
    /// and Tor circuit isolation. The fan-in validates the entire supplied collection before opening any
    /// route and then feeds every group into one shared runtime authority.
    struct RecipientRouteGroup: Sendable {
        let recipient: Transport.RecipientCapability
        let routes: [RelayRoute]
        let subscriptionIdentifiers: [
            RelayEndpoint: Nostr.SubscriptionIdentifier
        ]

        init(
            recipient: Transport.RecipientCapability,
            routes: [RelayRoute],
            subscriptionIdentifiers: [
                RelayEndpoint: Nostr.SubscriptionIdentifier
            ]
        ) {
            self.recipient = recipient
            self.routes = routes
            self.subscriptionIdentifiers = subscriptionIdentifiers
        }

    }

    /// Runtime lifecycle operations consumed by fan-in after authorized composition.
    ///
    /// The production value wraps one authenticated ingress. Focused transport tests may inject
    /// an inert endpoint, but this value cannot construct an ingress or runtime driver.
    struct RuntimeEndpoint: Sendable {
        private let startOperation: @Sendable () async -> Bool
        private let stateOperation: @Sendable () async -> Ingress.State
        private let submitOperation: @Sendable (Nostr.Event) async -> Ingress.Decision
        private let sourceTerminationOperation: @Sendable (
            OpalFusion.Mosaic.OpalMainnetAlpha.InputSourceTermination
        ) async -> Bool
        private let stopOperation: @Sendable () async -> Void
        private let waitOperation: @Sendable () async -> Driver.State?

        init(
            start: @escaping @Sendable () async -> Bool,
            state: @escaping @Sendable () async -> Ingress.State,
            submit: @escaping @Sendable (Nostr.Event) async -> Ingress.Decision,
            inputSourceDidTerminate: @escaping @Sendable (
                OpalFusion.Mosaic.OpalMainnetAlpha.InputSourceTermination
            ) async -> Bool,
            stop: @escaping @Sendable () async -> Void,
            waitForTermination: @escaping @Sendable () async -> Driver.State?
        ) {
            startOperation = start
            stateOperation = state
            submitOperation = submit
            sourceTerminationOperation = inputSourceDidTerminate
            stopOperation = stop
            waitOperation = waitForTermination
        }

        init(ingress: Ingress) {
            self.init(
                start: { await ingress.start() },
                state: { await ingress.state },
                submit: { await ingress.submit($0) },
                inputSourceDidTerminate: {
                    await ingress.inputSourceDidTerminate($0)
                },
                stop: { await ingress.stop() },
                waitForTermination: { await ingress.waitForTermination() }
            )
        }

        func start() async -> Bool { await startOperation() }
        func state() async -> Ingress.State { await stateOperation() }
        func submit(_ event: Nostr.Event) async -> Ingress.Decision {
            await submitOperation(event)
        }
        func inputSourceDidTerminate(
            _ termination: OpalFusion.Mosaic.OpalMainnetAlpha
                .InputSourceTermination
        ) async -> Bool {
            await sourceTerminationOperation(termination)
        }
        func stop() async { await stopOperation() }
        func waitForTermination() async -> Driver.State? {
            await waitOperation()
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
