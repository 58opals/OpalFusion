// OpalFusion+Client+Session.swift

public extension OpalFusion.Client {
    actor Session {
        private let configuration: OpalFusion.Client.Configuration
        private let genesisHash: [UInt8]?
        private let joinPools: OpalFusion.ProtocolModel.JoinPools
        private let participantReservationSource: any OpalFusion.Host.ParticipantReservationSource
        private let transactionAssembler: any OpalFusion.Host.TransactionAssembler
        private let eventObserver: (any OpalFusion.Host.EventObserver)?
        private let stateObserver: (any OpalFusion.Client.StateObserver)?
        private let reconnectPolicy: OpalFusion.Client.ReconnectPolicy
        private let dependencies: DependencyContext
        private var runtimeDriver: OpalFusion.Runtime.LiveRuntimeDriver?
        private var runtimeDriverGeneration: Int
        private var isActive: Bool
        private var retryAttempt: Int
        private var pendingRetryTask: Task<Void, Never>?
        private var lastEmittedSnapshot: OpalFusion.Client.Session.Snapshot

        public init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            participantReservationSource: any OpalFusion.Host.ParticipantReservationSource,
            transactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            stateObserver: (any OpalFusion.Client.StateObserver)? = nil,
            reconnectPolicy: OpalFusion.Client.ReconnectPolicy = .disabled
        ) {
            self.configuration = configuration
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.participantReservationSource = participantReservationSource
            self.transactionAssembler = transactionAssembler
            self.eventObserver = eventObserver
            self.stateObserver = stateObserver
            self.reconnectPolicy = reconnectPolicy
            self.dependencies = .defaults
            self.runtimeDriver = nil
            self.runtimeDriverGeneration = 0
            self.isActive = false
            self.retryAttempt = 0
            self.pendingRetryTask = nil
            self.lastEmittedSnapshot = .init()
        }

        internal init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            participantReservationSource: any OpalFusion.Host.ParticipantReservationSource,
            transactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            stateObserver: (any OpalFusion.Client.StateObserver)? = nil,
            reconnectPolicy: OpalFusion.Client.ReconnectPolicy = .disabled,
            workflow: OpalFusion.Execution.WorkflowContext? = nil,
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443,
            nowProvider: @escaping @Sendable () async -> OpalFusion.Execution.Instant = {
                .now()
            },
            clockTickInterval: Duration = .milliseconds(250),
            primaryTransportFactory: @escaping @Sendable () async -> (any OpalFusion.Runtime.PrimaryTransporting)? = { nil },
            covertTransportFactory: @escaping @Sendable () async -> (any OpalFusion.Runtime.CovertTransporting)? = { nil },
            snapshotDeliveryHook: @escaping @Sendable (
                OpalFusion.Client.Session.Snapshot
            ) async -> Void = { _ in }
        ) {
            self.configuration = configuration
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.participantReservationSource = participantReservationSource
            self.transactionAssembler = transactionAssembler
            self.eventObserver = eventObserver
            self.stateObserver = stateObserver
            self.reconnectPolicy = reconnectPolicy
            self.dependencies = .init(
                workflow: workflow,
                baseline: baseline,
                nowProvider: nowProvider,
                clockTickInterval: clockTickInterval,
                primaryTransportFactory: primaryTransportFactory,
                covertTransportFactory: covertTransportFactory,
                snapshotDeliveryHook: snapshotDeliveryHook
            )
            self.runtimeDriver = nil
            self.runtimeDriverGeneration = 0
            self.isActive = false
            self.retryAttempt = 0
            self.pendingRetryTask = nil
            self.lastEmittedSnapshot = .init()
        }

        public func start() async {
            guard isActive == false else {
                return
            }

            isActive = true
            retryAttempt = 0
            pendingRetryTask?.cancel()
            pendingRetryTask = nil
            await updateSnapshotIfNeeded(.init())

            await startRuntimeDriver()
        }

        public func stop() async {
            guard isActive || runtimeDriver != nil || pendingRetryTask != nil else {
                return
            }

            isActive = false
            pendingRetryTask?.cancel()
            pendingRetryTask = nil

            guard let runtimeDriver else {
                runtimeDriverGeneration += 1
                await updateSnapshotIfNeeded(stoppedSnapshot())
                return
            }

            await runtimeDriver.stop()
            self.runtimeDriver = nil
            runtimeDriverGeneration += 1
            await updateSnapshotIfNeeded(stoppedSnapshot())
        }

        public func snapshot() async -> OpalFusion.Client.Session.Snapshot {
            if let runtimeDriver {
                return OpalFusion.Client.Session.Snapshot(
                    await runtimeDriver.snapshot()
                )
            }

            return lastEmittedSnapshot
        }

        private func startRuntimeDriver() async {
            guard isActive else {
                return
            }

            runtimeDriverGeneration += 1
            let runtimeDriverGeneration = self.runtimeDriverGeneration
            let runtimeDriver = await makeRuntimeDriver(
                generation: runtimeDriverGeneration
            )
            self.runtimeDriver = runtimeDriver

            await runtimeDriver.start()
            guard isCurrentRuntimeDriver(runtimeDriver, generation: runtimeDriverGeneration) else {
                return
            }

            let runtimeSnapshot = await runtimeDriver.snapshot()
            let snapshot = OpalFusion.Client.Session.Snapshot(runtimeSnapshot)
            await updateSnapshotIfNeeded(snapshot)

            if snapshot.state.isConnected == false,
               snapshot.lastError != nil,
               isCurrentRuntimeDriver(runtimeDriver, generation: runtimeDriverGeneration) {
                await completeCurrentDriverAfterFailure(
                    snapshot: runtimeSnapshot,
                    generation: runtimeDriverGeneration
                )
            }
        }

        private func makeRuntimeDriver(
            generation: Int
        ) async -> OpalFusion.Runtime.LiveRuntimeDriver {
            let primaryTransportFactory = dependencies.primaryTransportFactory
            let covertTransportFactory = dependencies.covertTransportFactory
            return OpalFusion.Runtime.LiveRuntimeDriver(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                workflow: dependencies.workflow,
                participantReservationSource: participantReservationSource,
                transactionAssembler: transactionAssembler,
                eventObserver: eventObserver,
                snapshotSink: { snapshot in
                    await self.receive(snapshot, generation: generation)
                },
                baseline: dependencies.baseline,
                nowProvider: dependencies.nowProvider,
                clockTickInterval: dependencies.clockTickInterval,
                primaryTransportFactory: { configuration in
                    if let primaryTransport = await primaryTransportFactory() {
                        return primaryTransport
                    }

                    return OpalFusion.Runtime.LivePrimaryTransport(
                        host: configuration.coordinatorHost,
                        port: configuration.coordinatorPort,
                        requiresTLS: configuration.coordinatorRequiresTLS
                    )
                },
                covertTransportFactory: { configuration in
                    if let covertTransport = await covertTransportFactory() {
                        return covertTransport
                    }

                    return OpalFusion.Runtime.LiveCovertTransport(
                        torSocks5: configuration.torSocks5
                    )
                }
            )
        }

        private func receive(
            _ snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot,
            generation: Int
        ) async {
            guard isCurrentGeneration(generation) else {
                return
            }

            let sessionSnapshot = OpalFusion.Client.Session.Snapshot(snapshot)
            await dependencies.snapshotDeliveryHook(sessionSnapshot)
            guard isCurrentGeneration(generation) else {
                return
            }
            await updateSnapshotIfNeeded(sessionSnapshot)
            guard isCurrentGeneration(generation) else {
                return
            }

            if sessionSnapshot.state.isConnected == false,
               sessionSnapshot.lastError != nil {
                await completeCurrentDriverAfterFailure(
                    snapshot: snapshot,
                    generation: generation
                )
            }
        }

        private func completeCurrentDriverAfterFailure(
            snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot,
            generation: Int
        ) async {
            guard isCurrentGeneration(generation),
                  runtimeDriver != nil else {
                return
            }

            runtimeDriver = nil

            guard isActive,
                  snapshot.allowsReconnect,
                  snapshot.lastError == .transportUnavailable else {
                isActive = false
                return
            }

            let nextAttempt = retryAttempt + 1
            guard let retryDelay = reconnectPolicy.delay(
                forRetryAttempt: nextAttempt
            ) else {
                isActive = false
                return
            }

            retryAttempt = nextAttempt
            await scheduleRetry(
                attempt: nextAttempt,
                delay: retryDelay
            )
        }

        private func scheduleRetry(
            attempt: Int,
            delay: Duration
        ) async {
            let retryDelayMilliseconds = delay.opalFusionMillisecondsRoundedUp
            OpalFusionDiagnostics.record(
                OpalFusion.Diagnostics.Events.primaryRetryScheduled,
                category: OpalFusion.Diagnostics.Categories.primary,
                fields: [
                    OpalFusionDiagnostics.makeOperationField("primary_reconnect"),
                    OpalFusionDiagnostics.retryAttemptField(attempt),
                    OpalFusionDiagnostics.retryDelayMillisecondsField(retryDelayMilliseconds)
                ]
            )
            let event = OpalFusion.Client.Diagnostics.Event(
                kind: .retry,
                summary: "Primary reconnect scheduled",
                retryAttempt: attempt,
                retryDelayMilliseconds: retryDelayMilliseconds,
                handshakeStage: lastEmittedSnapshot.diagnostics.handshakeStage
            )
            let diagnostics = lastEmittedSnapshot.diagnostics
                .withRetry(attempt: attempt, delay: delay)
                .appending(event)
            await updateSnapshotIfNeeded(
                lastEmittedSnapshot.withDiagnostics(diagnostics)
            )

            let scheduledGeneration = runtimeDriverGeneration
            pendingRetryTask?.cancel()
            pendingRetryTask = Task { [delay, scheduledGeneration] in
                do {
                    try await Task.sleep(for: delay)
                } catch {
                    return
                }

                await self.runScheduledRetry(generation: scheduledGeneration)
            }
        }

        private func runScheduledRetry(
            generation: Int
        ) async {
            guard isActive,
                  isCurrentGeneration(generation) else {
                return
            }

            pendingRetryTask = nil
            await startRuntimeDriver()
        }

        private func isCurrentRuntimeDriver(
            _ runtimeDriver: OpalFusion.Runtime.LiveRuntimeDriver,
            generation: Int
        ) -> Bool {
            self.runtimeDriver === runtimeDriver && isCurrentGeneration(generation)
        }

        private func isCurrentGeneration(_ generation: Int) -> Bool {
            generation == runtimeDriverGeneration
        }

        private func stoppedSnapshot() -> OpalFusion.Client.Session.Snapshot {
            .init(
                state: .init(),
                lastError: nil,
                lastErrorSummary: nil,
                diagnostics: lastEmittedSnapshot.diagnostics
                    .withoutFailure()
                    .withRetry(attempt: nil, delay: nil)
                    .withHandshakeStage(.notStarted)
                    .withActivity(.stopped),
                coordinatorStatus: lastEmittedSnapshot.coordinatorStatus
            )
        }

        private func updateSnapshotIfNeeded(
            _ snapshot: OpalFusion.Client.Session.Snapshot
        ) async {
            if snapshot.state.isConnected,
               snapshot.lastError == nil {
                retryAttempt = 0
            }

            guard snapshot != lastEmittedSnapshot else {
                return
            }

            lastEmittedSnapshot = snapshot
            await stateObserver?.receive(snapshot)
        }
    }
}

private extension OpalFusion.Client.Session.Snapshot {
    init(_ snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot) {
        self.init(
            state: snapshot.clientState,
            lastError: snapshot.lastError,
            lastErrorSummary: snapshot.lastErrorSummary,
            diagnostics: snapshot.diagnostics,
            coordinatorStatus: snapshot.coordinatorStatus
        )
    }

    func withDiagnostics(
        _ diagnostics: OpalFusion.Client.Diagnostics
    ) -> Self {
        .init(
            state: state,
            lastError: lastError,
            lastErrorSummary: lastErrorSummary,
            diagnostics: diagnostics,
            coordinatorStatus: coordinatorStatus
        )
    }
}
