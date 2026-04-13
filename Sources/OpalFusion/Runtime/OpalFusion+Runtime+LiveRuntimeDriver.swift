// OpalFusion+Runtime+LiveRuntimeDriver.swift

extension OpalFusion.Runtime {
    actor LiveRuntimeDriver {
        struct Snapshot: Sendable, Equatable {
            let clientState: OpalFusion.Client.State
            let lastError: OpalFusion.Client.Error?
            let lastErrorSummary: String?
        }

        typealias SnapshotSink = @Sendable (
            OpalFusion.Runtime.LiveRuntimeDriver.Snapshot
        ) async -> Void
        typealias HostEventSink = @Sendable (
            OpalFusion.Round.Identifier?,
            OpalFusion.Host.Event
        ) async -> Void

        private var runtimeSession: OpalFusion.Runtime.PrimaryRuntimeSession
        private let participantInputProvider: any OpalFusion.Host.ParticipantInputProvider
        private let transactionAssembler: any OpalFusion.Host.TransactionAssembler
        private let eventObserver: (any OpalFusion.Host.EventObserver)?
        private let hostEventSink: HostEventSink
        private let snapshotSink: SnapshotSink
        private let primaryTransport: any OpalFusion.Runtime.PrimaryTransporting
        private let covertTransport: any OpalFusion.Runtime.CovertTransporting
        private let nowProvider: @Sendable () -> OpalFusion.Execution.Instant
        private let clockTickInterval: Duration
        private var primaryReadTask: Task<Void, Never>?
        private var clockTask: Task<Void, Never>?
        private var isRunning: Bool
        private var lastEmittedSnapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot?

        init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            workflow: OpalFusion.Execution.WorkflowContext? = nil,
            participantInputProvider: any OpalFusion.Host.ParticipantInputProvider,
            transactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            hostEventSink: @escaping HostEventSink = { _, _ in },
            snapshotSink: @escaping SnapshotSink = { _ in },
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443,
            nowProvider: @escaping @Sendable () -> OpalFusion.Execution.Instant = {
                .now()
            },
            clockTickInterval: Duration = .milliseconds(250),
            primaryTransport: (any OpalFusion.Runtime.PrimaryTransporting)? = nil,
            covertTransport: (any OpalFusion.Runtime.CovertTransporting)? = nil
        ) {
            self.runtimeSession = .init(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                workflow: workflow,
                baseline: baseline
            )
            self.participantInputProvider = participantInputProvider
            self.transactionAssembler = transactionAssembler
            self.eventObserver = eventObserver
            self.hostEventSink = hostEventSink
            self.snapshotSink = snapshotSink
            self.primaryTransport = primaryTransport ?? OpalFusion.Runtime.LivePrimaryTransport(
                host: configuration.coordinatorHost,
                port: configuration.coordinatorPort
            )
            self.covertTransport = covertTransport ?? OpalFusion.Runtime.LiveCovertTransport(
                torSocks5: configuration.torSocks5
            )
            self.nowProvider = nowProvider
            self.clockTickInterval = clockTickInterval
            self.primaryReadTask = nil
            self.clockTask = nil
            self.isRunning = false
            self.lastEmittedSnapshot = nil
        }

        func start() async {
            guard isRunning == false else {
                return
            }
            isRunning = true

            if let summary = OpalFusion.Runtime.validateConfiguration(
                runtimeSession.engine.session.configuration
            ) {
                await handle(.invalidConfiguration(summary: summary))
                await tearDownTransports()
                return
            }

            startClockLoop()

            do {
                let inboundStream = try await primaryTransport.connect()
                startPrimaryReadLoop(inboundStream)
                await handle(.connected)
            } catch {
                await handle(
                    .primaryTransportFailed(
                        summary: "Primary connect failed: \(String(describing: error))"
                    )
                )
                await tearDownTransports()
            }
        }

        func stop() async {
            await tearDownTransports()
        }

        func snapshot() -> OpalFusion.Runtime.LiveRuntimeDriver.Snapshot {
            .init(
                clientState: runtimeSession.clientState,
                lastError: runtimeSession.lastError,
                lastErrorSummary: runtimeSession.lastErrorSummary
            )
        }

        private func startPrimaryReadLoop(
            _ inboundStream: AsyncThrowingStream<[UInt8], Error>
        ) {
            primaryReadTask?.cancel()
            primaryReadTask = Task { [inboundStream] in
                do {
                    for try await bytes in inboundStream {
                        await self.handle(.receivedPrimaryBytes(bytes))
                    }
                    await self.handle(.disconnected)
                } catch {
                    await self.handle(
                        .primaryTransportFailed(
                            summary: "Primary read failed: \(String(describing: error))"
                        )
                    )
                }
            }
        }

        private func startClockLoop() {
            clockTask?.cancel()
            clockTask = Task { [clockTickInterval] in
                while Task.isCancelled == false {
                    do {
                        try await Task.sleep(for: clockTickInterval)
                    } catch {
                        return
                    }

                    if Task.isCancelled {
                        return
                    }

                    await self.handle(.clockAdvanced)
                }
            }
        }

        private func handle(
            _ input: OpalFusion.Runtime.PrimaryRuntimeSession.Input
        ) async {
            let effects = runtimeSession.apply(
                input: input,
                now: nowProvider()
            )

            for effect in effects {
                await process(effect)
            }

            if runtimeSession.engine.session.connectionSubstate != .inRound {
                await covertTransport.reset()
            }

            if runtimeSession.engine.session.connectionSubstate == .failed ||
                runtimeSession.engine.session.connectionSubstate == .disconnected {
                await tearDownTransports()
            }

            await emitSnapshotIfNeeded()
        }

        private func process(
            _ effect: OpalFusion.Runtime.PrimaryRuntimeSession.Effect
        ) async {
            switch effect {
            case let .writePrimaryBytes(bytes):
                do {
                    try await primaryTransport.write(bytes)
                } catch {
                    await handle(
                        .primaryTransportFailed(
                            summary: "Primary write failed: \(String(describing: error))"
                        )
                    )
                }
            case let .prepareCovertEndpoint(plan):
                Task {
                    do {
                        try await self.covertTransport.prepare(plan)
                        await self.handle(.covertPrepared)
                    } catch {
                        await self.handle(
                            .covertPreparationFailed(
                                summary: "Covert endpoint preparation failed: \(String(describing: error))"
                            )
                        )
                    }
                }
            case let .performCovertRequest(request):
                Task {
                    do {
                        let responseBytes = try await self.covertTransport.perform(request)
                        await self.handle(.receivedCovertResponseBytes(responseBytes))
                    } catch {
                        await self.handle(
                            .covertRequestFailed(
                                summary: "Covert request failed: \(String(describing: error))"
                            )
                        )
                    }
                }
            case let .requestParticipantReservation(roundIdentifier):
                Task {
                    do {
                        let reservation = try await self.participantInputProvider.participantReservation(
                            for: roundIdentifier
                        )
                        await self.handle(.participantReservationLoaded(reservation))
                    } catch {
                        await self.handle(.participantReservationRejected)
                    }
                }
            case let .requestTransactionFinalization(roundIdentifier, proposal):
                Task {
                    do {
                        let transaction = try await self.transactionAssembler.finalizeTransaction(
                            for: roundIdentifier,
                            proposal: proposal
                        )
                        await self.handle(.finalizedTransactionLoaded(transaction))
                    } catch {
                        await self.handle(.transactionFinalizationRejected)
                    }
                }
            case let .emitHostEvent(roundIdentifier, event):
                await hostEventSink(roundIdentifier, event)

                if let roundIdentifier {
                    await eventObserver?.receive(event, for: roundIdentifier)
                }
            }
        }

        private func tearDownTransports() async {
            guard isRunning else {
                return
            }

            isRunning = false
            primaryReadTask?.cancel()
            primaryReadTask = nil
            clockTask?.cancel()
            clockTask = nil
            await primaryTransport.close()
            await covertTransport.reset()
        }

        private func emitSnapshotIfNeeded() async {
            let snapshot = snapshot()
            guard snapshot != lastEmittedSnapshot else {
                return
            }

            lastEmittedSnapshot = snapshot
            await snapshotSink(snapshot)
        }
    }
}
