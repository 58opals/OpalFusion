// OpalFusion+Client+Session+ImplementationGroup1.swift

import OpalDiagnostics

extension OpalFusion.Client.Session {
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

    func startRuntimeDriver() async {
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

        let runtimeSnapshot = await runtimeDriver.currentSnapshot
        let snapshot = OpalFusion.Client.Session.Snapshot(runtimeSnapshot: runtimeSnapshot)
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

    func makeRuntimeDriver(
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

    func receive(
        _ snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot,
        generation: Int
    ) async {
        guard isCurrentGeneration(generation) else {
            return
        }

        let sessionSnapshot = OpalFusion.Client.Session.Snapshot(runtimeSnapshot: snapshot)
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

    func completeCurrentDriverAfterFailure(
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
        guard let retryDelay = reconnectPolicy.calculateDelay(
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
}
