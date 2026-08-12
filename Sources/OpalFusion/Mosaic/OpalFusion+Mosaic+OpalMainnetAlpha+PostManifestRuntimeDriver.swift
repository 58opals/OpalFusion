// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRuntimeDriver.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Selects exactly one post-manifest mainnet-alpha role executor.
    ///
    /// Its attempt-scoped ingress supplies one serialized stream of signed gift wraps and
    /// selects a sealed recipient capability. This driver derives the exact attempt context
    /// from its bootstrap and authenticates each event before the selected coordinator sees it.
    /// The selected coordinator owns ordering, terminal state, role-specific disposition,
    /// and recovery-required classification; only the contributor coordinator owns wallet
    /// disposition. Durable recovery remains app-owned. This façade owns no tasks,
    /// recipient keys, relay connections, or broadcast policy.
    struct PostManifestRuntimeDriver: Sendable {
        private enum Coordinator: Sendable {
            case contributor(ReservationCoordinator)
            case conductor(ConductorCoordinator)
        }

        private let coordinator: Coordinator
        private let transportContext: Transport.RuntimeContext

        var state: State {
            get async {
                switch coordinator {
                case let .contributor(coordinator):
                    .contributor(await coordinator.state)
                case let .conductor(coordinator):
                    .conductor(await coordinator.state)
                }
            }
        }

        init(
            claimedRuntimeConstruction _: PostManifestAttemptTransportOwner
                .InboundRuntimeProvisioning.ClaimedRuntimeConstruction,
            bootstrap: Bootstrap,
            dependencies: RoleDependencies,
            admissionJournal: AdmissionJournal
        ) throws(InitializationError) {
            let runtimeSession: Session
            do {
                runtimeSession = try .init(
                    validatedAttempt: bootstrap.validatedAttempt,
                    attemptIdentifier: bootstrap.attemptIdentifier,
                    generationIdentifier: bootstrap.generationIdentifier,
                    materialIdentifier: bootstrap.materialIdentifier,
                    localControlIdentity: bootstrap.localControlIdentity,
                    proposalValidation: bootstrap.proposalValidation
                )
            } catch {
                throw .runtimeConstructionFailed
            }

            let localRole = runtimeSession.context.localRole
            guard dependencies.role == localRole else {
                throw .dependencyRoleMismatch(
                    expected: localRole,
                    received: dependencies.role
                )
            }
            transportContext = .init(
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                phaseStartUnixSeconds:
                    bootstrap.proposalValidation.core.deadlines.phaseStart
            )
            switch dependencies {
            case let .contributor(dependencies):
                guard dependencies.maximumPendingInputCount > 0 else {
                    throw .invalidInputBufferLimit
                }
                do {
                    coordinator = .contributor(
                        try ReservationCoordinator(
                            runtimeSession: runtimeSession,
                            dependencies: dependencies.coordinatorDependencies,
                            admissionJournal: admissionJournal
                        )
                    )
                } catch {
                    throw .runtimeConstructionFailed
                }

            case let .conductor(dependencies):
                guard dependencies.maximumPendingInputCount > 0 else {
                    throw .invalidInputBufferLimit
                }
                do {
                    coordinator = .conductor(
                        try ConductorCoordinator(
                            runtimeSession: runtimeSession,
                            dependencies: dependencies,
                            admissionJournal: admissionJournal
                        )
                    )
                } catch {
                    throw .runtimeConstructionFailed
                }
            }
        }

        /// Starts the selected role executor once.
        func start() async {
            switch coordinator {
            case let .contributor(coordinator):
                await coordinator.start()
            case let .conductor(coordinator):
                await coordinator.start()
            }
        }

        /// Authenticates and routes one signed gift wrap without exposing local authority inputs.
        @discardableResult
        func submit(
            _ giftWrap: OpalFusion.Mosaic.NostrNamespace.Event,
            to recipient: Transport.RecipientCapability,
            currentUnixSeconds: UInt64
        ) async throws(Transport.Failure) -> Bool {
            let delivery: Transport.AuthenticatedDelivery
            switch recipient.channel {
            case .control:
                delivery = try Transport.openControl(
                    giftWrap,
                    context: transportContext,
                    recipientSigningKey: recipient.signingKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            case .anonymous:
                delivery = try Transport.openAnonymous(
                    giftWrap,
                    context: transportContext,
                    recipientSigningKey: recipient.signingKey,
                    currentUnixSeconds: currentUnixSeconds
                )
            }
            return await route(delivery)
        }

        private func route(
            _ delivery: Transport.AuthenticatedDelivery
        ) async -> Bool {
            switch (coordinator, delivery.storage) {
            case let (.contributor(coordinator), .control(delivery)):
                await coordinator.submitAuthenticatedControl(delivery)
            case (.contributor, .anonymous):
                false
            case let (.conductor(coordinator), .control(delivery)):
                await coordinator.submitAuthenticatedControl(delivery)
            case let (.conductor(coordinator), .anonymous(delivery)):
                await coordinator.submitAuthenticatedAnonymous(delivery)
            }
        }

        /// Orders authenticated-source closure behind inputs accepted by the selected coordinator.
        @discardableResult
        func inputSourceDidTerminate(
            _ termination: InputSourceTermination
        ) async -> Bool {
            switch coordinator {
            case let .contributor(coordinator):
                return await coordinator.inputSourceDidTerminate(termination)
            case let .conductor(coordinator):
                return await coordinator.inputSourceDidTerminate(termination)
            }
        }

        /// Requests cancellation without cancelling an in-flight coordinator dependency.
        func stop() async {
            switch coordinator {
            case let .contributor(coordinator):
                await coordinator.stop()
            case let .conductor(coordinator):
                await coordinator.stop()
            }
        }

        /// Waits for ordered role disposition and returns the selected coordinator state.
        func waitForTermination() async -> State {
            switch coordinator {
            case let .contributor(coordinator):
                await coordinator.waitForTermination()
                return .contributor(await coordinator.state)
            case let .conductor(coordinator):
                await coordinator.waitForTermination()
                return .conductor(await coordinator.state)
            }
        }

    }
}
