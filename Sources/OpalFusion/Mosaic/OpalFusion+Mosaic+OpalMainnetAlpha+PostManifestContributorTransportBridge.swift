// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestContributorTransportBridge.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Binds one contributor's ordered runtime publications to post-manifest transport.
    ///
    /// The actor eagerly binds the control sender and its exact inbound control mailbox, then
    /// installs the anonymous publication path only after the caller's lease-backed local
    /// material has been constructed and revalidated. It owns neither wallet disposition,
    /// semantic loopback, relay ingress lifecycle, timing policy, persistence, retry, nor
    /// broadcast permission.
    actor PostManifestContributorTransportBridge {
        private let context: ControlBridge.Context
        private let inboundAttemptBinding: FanIn.AttemptBinding
        private let controlBridge: ControlBridge
        private let localControlRecipientCapability: Transport
            .RecipientCapability
        private let relaySelection: PostManifestRelaySelectionValidation
        private let codingLimits: Nostr.RelayMessageCodingLimits
        private let maximumPendingRelayOutputCount: Int
        private let dependencies: Dependencies
        private var anonymousBridge: AnonymousBridge?
        private var activeMaterialTask: Task<MaterialTaskResult, Never>?
        private var activePublicationTask: Task<PublicationTaskResult, Never>?
        private var terminationWaiters: [
            CheckedContinuation<State, Never>
        ] = []

        private enum MaterialTaskResult: Sendable {
            case success(LocalContributionMaterial)
            case failed
        }

        private enum PublicationTaskResult: Sendable {
            case success
            case failed
            case cancelled
        }

        private(set) var state: State = .awaitingMaterial

        init(
            bootstrap: Driver.Bootstrap,
            manifest: RoundManifest,
            controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
            controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey,
            controlRecipients: [ControlBridge.Recipient],
            localControlRecipientCapability: Transport.RecipientCapability,
            relaySelection: PostManifestRelaySelectionValidation,
            codingLimits: Nostr.RelayMessageCodingLimits,
            maximumPendingRelayOutputCount: Int,
            dependencies: Dependencies
        ) throws(InitializationError) {
            let context: ControlBridge.Context
            do {
                context = try .init(
                    validating: manifest,
                    against: bootstrap
                )
            } catch let error {
                throw .invalidContext(error)
            }
            guard context.roster.contributors.contains(
                context.localControlIdentity
            ) else {
                throw .localPeerIsNotContributor
            }
            guard let localRecipient = controlRecipients.first(where: {
                $0.controlIdentity == context.localControlIdentity
            }) else {
                throw .missingLocalControlRecipient
            }
            guard localControlRecipientCapability.channel == .control,
                  localControlRecipientCapability.signingKey
                    .bip340VerificationKey.rawRepresentation
                    == localRecipient.eventVerificationKey.rawRepresentation else {
                throw .localControlRecipientMismatch
            }

            let controlPublisher: ControlPublisher
            do {
                controlPublisher = try .init(
                    context: context,
                    recipients: controlRecipients,
                    relaySelection: relaySelection,
                    codingLimits: codingLimits,
                    maximumPendingRelayOutputCount:
                        maximumPendingRelayOutputCount,
                    provideRoutes: dependencies.provideControlRoutes
                )
            } catch let error {
                throw .controlPublisher(error)
            }
            let controlBridge: ControlBridge
            do {
                controlBridge = try .init(
                    context: context,
                    controlSigningKey: controlSigningKey,
                    eventSigningKey: controlEventSigningKey,
                    recipients: controlRecipients,
                    dependencies: .init(
                        makeLayerTimestamps:
                            dependencies.makeControlLayerTimestamps,
                        makeSignatureAuxiliaryRandomness:
                            dependencies
                                .makeControlSignatureAuxiliaryRandomness,
                        handoffGiftWrapBatch: { batch in
                            try await controlPublisher.publish(batch)
                        }
                    )
                )
            } catch let error {
                throw .controlBridge(error)
            }

            self.context = context
            inboundAttemptBinding = .init(bootstrap: bootstrap)
            self.controlBridge = controlBridge
            self.localControlRecipientCapability =
                localControlRecipientCapability
            self.relaySelection = relaySelection
            self.codingLimits = codingLimits
            self.maximumPendingRelayOutputCount =
                maximumPendingRelayOutputCount
            self.dependencies = dependencies
        }

        /// Produces the exact contributor callbacks consumed by the reservation coordinator.
        ///
        /// The returned closures retain this one-shot bridge. The bridge does not retain the
        /// returned dependencies, avoiding a reference cycle.
        nonisolated func makeExecutionDependencies(
            transactionHost: any OpalFusion.Host.MosaicCompleteTransactionHost,
            previousOutputSource: any OpalFusion.Host.MosaicPreviousOutputSource,
            makeLocalContributionMaterial: @escaping @Sendable (
                Coordinator.ReservationEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> LocalContributionMaterial
        ) -> Coordinator.ExecutionDependencies {
            .init(
                transactionHost: transactionHost,
                previousOutputSource: previousOutputSource,
                makeLocalContributionMaterial: { [self] eligibility, lease in
                    try await bindLocalContributionMaterial(
                        eligibility,
                        lease: lease,
                        using: makeLocalContributionMaterial
                    )
                },
                publishPlayerCommit: { [self] validation in
                    try await publishPlayerCommit(validation)
                },
                publishAnonymousComponents: { [self] validation in
                    try await publishAnonymousComponents(validation)
                },
                publishPreSignAcknowledgement: { [self] validation in
                    try await publishPreSignAcknowledgement(validation)
                },
                publishLocalBCHSignatures: { [self] validation in
                    try await publishLocalBCHSignatures(validation)
                }
            )
        }

        /// Mints the only contributor control route group that this attempt may feed to fan-in.
        ///
        /// The capability was matched to the local control-recipient allocation at construction.
        func makeInboundControlRouteGroup(
            routes: [PostManifestRelayRoute],
            subscriptionIdentifiers: [
                PostManifestRelayEndpoint: Nostr.SubscriptionIdentifier
            ]
        ) throws(Failure) -> FanIn.RecipientRouteGroup {
            switch state {
            case let .draining(failure):
                throw failure
            case .terminal, .completed:
                throw .inputAfterTermination
            default:
                break
            }
            return .init(
                attemptBinding: inboundAttemptBinding,
                recipient: localControlRecipientCapability,
                routes: routes,
                subscriptionIdentifiers: subscriptionIdentifiers
            )
        }

        /// Requests terminal cancellation without awaiting the currently active callback.
        ///
        /// Material construction is allowed to return because it can straddle the wallet
        /// reservation boundary. Relay publication is cancelled. The active callback owns final
        /// drain and terminalization, so this method is safe when called reentrantly from an
        /// injected material, route, or permit authority.
        func requestStop() {
            switch state {
            case .terminal, .completed:
                return
            case .preparingMaterial:
                _ = reservePendingTermination(.cancelled)
            case .publishing:
                _ = reservePendingTermination(.cancelled)
                activePublicationTask?.cancel()
            case .draining:
                return
            default:
                _ = terminate(.cancelled)
            }
        }

        /// Waits for completed publication or terminal drain.
        ///
        /// Lifecycle owners may call this after `requestStop()`. Dependency callbacks must return
        /// instead of awaiting their own enclosing operation's termination.
        func waitForTermination() async -> State {
            switch state {
            case .terminal, .completed:
                return state
            default:
                return await withCheckedContinuation { continuation in
                    terminationWaiters.append(continuation)
                }
            }
        }

        private func bindLocalContributionMaterial(
            _ eligibility: Coordinator.ReservationEligibility,
            lease: OpalFusion.Host.MosaicReservationLease,
            using makeMaterial: @escaping @Sendable (
                Coordinator.ReservationEligibility,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> LocalContributionMaterial
        ) async throws(Failure) -> LocalContributionMaterial {
            try beginMaterialConstruction(eligibility)

            let task = Task { () -> MaterialTaskResult in
                do {
                    return .success(
                        try await makeMaterial(eligibility, lease)
                    )
                } catch {
                    return .failed
                }
            }
            activeMaterialTask = task
            let result = await task.value
            activeMaterialTask = nil

            if let pendingFailure = drainingFailure {
                throw finishPendingTermination(pendingFailure)
            }
            guard state == .preparingMaterial else {
                throw terminalFailure()
            }
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
            guard case let .success(material) = result else {
                throw terminate(.materialConstructionFailed)
            }
            guard material.reservationLease == lease else {
                throw terminate(.materialBindingFailed)
            }

            let materialContext: ControlBridge.Context
            do {
                materialContext = try .init(
                    validating: material,
                    against: eligibility.context
                )
            } catch {
                throw terminate(.materialBindingFailed)
            }
            guard materialContext == context else {
                throw terminate(.materialBindingFailed)
            }

            let anonymousPublisher: AnonymousPublisher
            do {
                anonymousPublisher = try .init(
                    context: context,
                    material: material,
                    relaySelection: relaySelection,
                    codingLimits: codingLimits,
                    maximumPendingRelayOutputCount:
                        maximumPendingRelayOutputCount,
                    provideRoutes: dependencies.provideAnonymousRoutes,
                    awaitPublicationPermit:
                        dependencies.awaitAnonymousPublicationPermit
                )
            } catch {
                throw terminate(.materialBindingFailed)
            }
            let anonymousBridge: AnonymousBridge
            do {
                anonymousBridge = try .init(
                    context: context,
                    material: material,
                    dependencies: .init(
                        makeLayerTimestamps:
                            dependencies.makeAnonymousLayerTimestamps,
                        handoffGiftWrapBatch: { batch in
                            try await anonymousPublisher.publish(batch)
                        }
                    )
                )
            } catch {
                throw terminate(.materialBindingFailed)
            }
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
            self.anonymousBridge = anonymousBridge
            state = .readyForPlayerCommit
            return material
        }

        private func publishPlayerCommit(
            _ validation: RuntimeSession.ReservationPublicationValidation
        ) async throws(Failure) {
            try beginPublication(
                .playerCommit,
                expected: .readyForPlayerCommit
            )
            let expiry = try expiry(for: .playerCommit)
            let controlBridge = controlBridge
            let task = startPublicationTask {
                try await controlBridge.publishPlayerCommit(
                    validation,
                    expiryUnixSeconds: expiry
                )
            }
            try await finishPublication(
                task,
                .playerCommit,
                next: .playerCommitPublished
            )
        }

        private func publishAnonymousComponents(
            _ validation: Coordinator.AnonymousComponentPublicationValidation
        ) async throws(Failure) {
            try beginPublication(
                .anonymousComponents,
                expected: .playerCommitPublished
            )
            let expiry = try expiry(for: .anonymousComponents)
            guard let anonymousBridge else {
                throw terminate(.materialBindingFailed)
            }
            let task = startPublicationTask {
                try await anonymousBridge.publishComponents(
                    validation,
                    expiryUnixSeconds: expiry
                )
            }
            try await finishPublication(
                task,
                .anonymousComponents,
                next: .anonymousComponentsPublished
            )
        }

        private func publishPreSignAcknowledgement(
            _ validation: OpalFusion.Mosaic.LocalAttempt
                .TranscriptInclusionValidation
        ) async throws(Failure) {
            try beginPublication(
                .preSignAcknowledgement,
                expected: .anonymousComponentsPublished
            )
            let expiry = try expiry(for: .preSignAcknowledgement)
            let controlBridge = controlBridge
            let task = startPublicationTask {
                try await controlBridge.publishPreSignAcknowledgement(
                    validation,
                    expiryUnixSeconds: expiry
                )
            }
            try await finishPublication(
                task,
                .preSignAcknowledgement,
                next: .preSignAcknowledgementPublished
            )
        }

        private func publishLocalBCHSignatures(
            _ validation: Coordinator.AnonymousBCHSignaturePublicationValidation
        ) async throws(Failure) {
            try beginPublication(
                .localBCHSignatures,
                expected: .preSignAcknowledgementPublished
            )
            let expiry = try expiry(for: .localBCHSignatures)
            guard let anonymousBridge else {
                throw terminate(.materialBindingFailed)
            }
            let task = startPublicationTask {
                try await anonymousBridge.publishBCHSignatures(
                    validation,
                    expiryUnixSeconds: expiry
                )
            }
            try await finishPublication(
                task,
                .localBCHSignatures,
                next: .completed
            )
        }

        private func beginMaterialConstruction(
            _ eligibility: Coordinator.ReservationEligibility
        ) throws(Failure) {
            switch state {
            case let .draining(failure):
                throw failure
            case .terminal, .completed:
                throw .inputAfterTermination
            default:
                break
            }
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
            guard state == .awaitingMaterial else {
                if state == .preparingMaterial {
                    throw reservePendingTermination(.concurrentOperation)
                }
                if isPublishing {
                    let failure = reservePendingTermination(
                        .concurrentOperation
                    )
                    activePublicationTask?.cancel()
                    throw failure
                }
                throw terminate(.invalidPublicationOrder)
            }
            guard eligibility.manifest == context.manifest,
                  eligibility.context.attemptIdentifier
                    == context.attemptIdentifier,
                  eligibility.context.generationIdentifier
                    == context.generationIdentifier,
                  eligibility.context.materialIdentifier
                    == context.materialIdentifier,
                  eligibility.context.localControlIdentity
                    == context.localControlIdentity,
                  eligibility.context.localRole == .contributor,
                  eligibility.context.roster == context.roster,
                  eligibility.context.proposalRoundIdentifier
                    == context.roundIdentifier else {
                throw terminate(.materialBindingFailed)
            }
            state = .preparingMaterial
        }

        private func beginPublication(
            _ publication: Publication,
            expected: State
        ) throws(Failure) {
            switch state {
            case let .draining(failure):
                throw failure
            case .terminal, .completed:
                throw .inputAfterTermination
            default:
                break
            }
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
            guard state == expected else {
                if state == .preparingMaterial || isPublishing {
                    let failure = reservePendingTermination(
                        .concurrentOperation
                    )
                    activePublicationTask?.cancel()
                    throw failure
                }
                throw terminate(.invalidPublicationOrder)
            }
            state = .publishing(publication)
        }

        private func expiry(
            for publication: Publication
        ) throws(Failure) -> UInt64 {
            let expiry: UInt64
            do {
                expiry = try dependencies.makeExpiryUnixSeconds(
                    publication
                )
            } catch {
                if Task.isCancelled {
                    throw terminate(.cancelled)
                }
                throw terminate(.expiryUnavailable(publication))
            }
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
            return expiry
        }

        private func startPublicationTask(
            _ operation: @escaping @Sendable () async throws -> Void
        ) -> Task<PublicationTaskResult, Never> {
            let task = Task { () -> PublicationTaskResult in
                do {
                    try await operation()
                    return .success
                } catch {
                    if Task.isCancelled {
                        return .cancelled
                    }
                    if let failure = error as? ControlBridge.Failure,
                       failure == .cancelled {
                        return .cancelled
                    }
                    if let failure = error as? AnonymousBridge.Failure,
                       failure == .cancelled {
                        return .cancelled
                    }
                    return .failed
                }
            }
            activePublicationTask = task
            return task
        }

        private func finishPublication(
            _ task: Task<PublicationTaskResult, Never>,
            _ publication: Publication,
            next: State
        ) async throws(Failure) {
            let result = await withTaskCancellationHandler {
                await task.value
            } onCancel: {
                task.cancel()
            }
            activePublicationTask = nil
            if let pendingFailure = drainingFailure {
                throw finishPendingTermination(pendingFailure)
            }
            guard state == .publishing(publication) else {
                throw terminalFailure()
            }
            guard !Task.isCancelled else {
                throw terminate(.cancelled)
            }
            switch result {
            case .success:
                state = next
                resumeTerminationWaitersIfNeeded()
            case .failed:
                throw terminate(.publicationFailed(publication))
            case .cancelled:
                throw terminate(.cancelled)
            }
        }

        private var isPublishing: Bool {
            if case .publishing = state { return true }
            return false
        }

        private func reservePendingTermination(_ failure: Failure) -> Failure {
            if let drainingFailure { return drainingFailure }
            if case let .terminal(existing) = state { return existing }
            state = .draining(failure)
            return failure
        }

        private var drainingFailure: Failure? {
            guard case let .draining(failure) = state else { return nil }
            return failure
        }

        private func finishPendingTermination(_ failure: Failure) -> Failure {
            if case let .terminal(existing) = state { return existing }
            if state == .completed { return .inputAfterTermination }
            state = .terminal(failure)
            resumeTerminationWaitersIfNeeded()
            return failure
        }

        @discardableResult
        private func terminate(_ failure: Failure) -> Failure {
            if case let .terminal(existing) = state {
                return existing
            }
            if case let .draining(existing) = state {
                return existing
            }
            if state == .completed {
                return .inputAfterTermination
            }
            state = .terminal(failure)
            resumeTerminationWaitersIfNeeded()
            return failure
        }

        private func resumeTerminationWaitersIfNeeded() {
            switch state {
            case .terminal, .completed:
                break
            default:
                return
            }
            let waiters = terminationWaiters
            terminationWaiters.removeAll(keepingCapacity: false)
            for waiter in waiters {
                waiter.resume(returning: state)
            }
        }

        private func terminalFailure() -> Failure {
            guard case let .terminal(failure) = state else {
                preconditionFailure(
                    "An in-flight transport operation can change only by terminalization."
                )
            }
            return failure
        }
    }
}
