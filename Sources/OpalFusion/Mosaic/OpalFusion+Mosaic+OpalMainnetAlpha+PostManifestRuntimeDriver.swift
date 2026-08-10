// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestRuntimeDriver.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Selects exactly one post-manifest mainnet-alpha role executor.
    ///
    /// An external adapter must submit one serialized stream of already-authenticated and decrypted
    /// values. The selected coordinator owns in-process ordering, terminal state, role-specific
    /// disposition, and recovery-required classification; only the contributor coordinator owns
    /// wallet disposition. Durable recovery remains app-owned. This façade owns no tasks, transport
    /// constants, private keys, or broadcast policy.
    struct PostManifestRuntimeDriver: Sendable {
        private enum Coordinator: Sendable {
            case contributor(ReservationCoordinator)
            case conductor(ConductorCoordinator)
        }

        private let coordinator: Coordinator

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
            bootstrap: Bootstrap,
            dependencies: RoleDependencies
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

            switch dependencies {
            case let .contributor(dependencies):
                guard dependencies.maximumPendingInputCount > 0 else {
                    throw .invalidInputBufferLimit
                }
                do {
                    coordinator = .contributor(
                        try ReservationCoordinator(
                            runtimeSession: runtimeSession,
                            dependencies: dependencies.coordinatorDependencies
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
                            dependencies: dependencies
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

        /// Routes one already-authenticated delivery without exposing local authority inputs.
        @discardableResult
        func submit(_ delivery: AuthenticatedDelivery) async -> Bool {
            switch (coordinator, delivery) {
            case let (.contributor(coordinator), .control(delivery)):
                await coordinator.submitControl(delivery)
            case (.contributor, .anonymous):
                false
            case let (.conductor(coordinator), .control(delivery)):
                await coordinator.submitControl(delivery)
            case let (.conductor(coordinator), .anonymous(delivery)):
                await coordinator.submitAnonymous(delivery)
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
