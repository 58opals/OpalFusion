// OpalFusion+Runtime+LiveRuntimeDriver.swift

import OSLog

extension OpalFusion.Runtime {
    actor LiveRuntimeDriver {
        private static let logger = Logger(
            subsystem: "OpalFusion",
            category: "LiveRuntimeDriver"
        )

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
        typealias PrimaryTransportFactory = @Sendable (
            OpalFusion.Client.Configuration
        ) -> any OpalFusion.Runtime.PrimaryTransporting

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
        private var covertOperationGeneration: UInt64
        private var hostOperationGeneration: UInt64

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
            primaryTransportFactory: PrimaryTransportFactory? = nil,
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
            if let primaryTransport {
                self.primaryTransport = primaryTransport
            } else if let primaryTransportFactory {
                self.primaryTransport = primaryTransportFactory(configuration)
            } else {
                self.primaryTransport = OpalFusion.Runtime.LivePrimaryTransport(
                    host: configuration.coordinatorHost,
                    port: configuration.coordinatorPort,
                    requiresTLS: configuration.coordinatorRequiresTLS
                )
            }
            self.covertTransport = covertTransport ?? OpalFusion.Runtime.LiveCovertTransport(
                torSocks5: configuration.torSocks5
            )
            self.nowProvider = nowProvider
            self.clockTickInterval = clockTickInterval
            self.primaryReadTask = nil
            self.clockTask = nil
            self.isRunning = false
            self.lastEmittedSnapshot = nil
            self.covertOperationGeneration = 0
            self.hostOperationGeneration = 0
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

            do {
                let inboundStream = try await primaryTransport.connect()
                startPrimaryReadLoop(inboundStream)
                await handle(.connected)
                if isRunning {
                    startClockLoop()
                }
            } catch {
                let summary = "Primary connect failed: \(String(describing: error))"
                Self.logger.debug(
                    "primary connect failure summary=\(summary, privacy: .public)"
                )
                await handle(
                    .primaryTransportFailed(
                        summary: summary
                    )
                )
                await tearDownTransports()
            }
        }

        func stop() async {
            guard isRunning else {
                return
            }

            await handle(.disconnected)
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
                    let summary = "Primary read failed: \(String(describing: error))"
                    Self.logger.debug(
                        "primary read failure summary=\(summary, privacy: .public)"
                    )
                    await self.handle(
                        .primaryTransportFailed(
                            summary: summary
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

                if hasTerminalConnectionState {
                    break
                }
            }

            if runtimeSession.engine.session.connectionSubstate != .inRound {
                invalidateCovertOperations()
                invalidateHostOperations()
                await covertTransport.reset()
            }

            if hasTerminalConnectionState {
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
                    let summary = "Primary write failed: \(String(describing: error))"
                    Self.logger.debug(
                        "primary write failure summary=\(summary, privacy: .public)"
                    )
                    await handle(
                        .primaryTransportFailed(
                            summary: summary
                        )
                    )
                }
            case let .prepareCovertEndpoint(plan):
                let generation = covertOperationGeneration
                Task {
                    do {
                        try await self.covertTransport.prepare(plan)
                        await self.handleCovertPreparedIfCurrent(
                            plan: plan,
                            generation: generation
                        )
                    } catch {
                        await self.handleCovertPreparationFailureIfCurrent(
                            summary: "Covert endpoint preparation failed: \(String(describing: error))",
                            plan: plan,
                            generation: generation
                        )
                    }
                }
            case let .performCovertRequest(request):
                let generation = covertOperationGeneration
                Task {
                    do {
                        let responseBytes = try await self.covertTransport.perform(request)
                        await self.handleCovertResponseIfCurrent(
                            responseBytes,
                            request: request,
                            generation: generation
                        )
                    } catch {
                        await self.handleCovertRequestFailureIfCurrent(
                            summary: "Covert request failed: \(String(describing: error))",
                            request: request,
                            generation: generation
                        )
                    }
                }
            case let .requestParticipantReservation(roundIdentifier):
                let generation = hostOperationGeneration
                Task {
                    do {
                        let reservation = try await self.participantInputProvider.participantReservation(
                            for: roundIdentifier
                        )
                        await self.handleParticipantReservationLoadedIfCurrent(
                            reservation,
                            roundIdentifier: roundIdentifier,
                            generation: generation
                        )
                    } catch {
                        await self.handleParticipantReservationRejectedIfCurrent(
                            roundIdentifier: roundIdentifier,
                            generation: generation
                        )
                    }
                }
            case let .requestTransactionFinalization(roundIdentifier, proposal):
                let generation = hostOperationGeneration
                Task {
                    do {
                        let transaction = try await self.transactionAssembler.finalizeTransaction(
                            for: roundIdentifier,
                            proposal: proposal
                        )
                        await self.handleFinalizedTransactionLoadedIfCurrent(
                            transaction,
                            roundIdentifier: roundIdentifier,
                            generation: generation
                        )
                    } catch {
                        await self.handleTransactionFinalizationRejectedIfCurrent(
                            roundIdentifier: roundIdentifier,
                            generation: generation
                        )
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
            invalidateCovertOperations()
            invalidateHostOperations()
            primaryReadTask?.cancel()
            primaryReadTask = nil
            clockTask?.cancel()
            clockTask = nil
            await primaryTransport.close()
            await covertTransport.reset()
        }

        private var hasTerminalConnectionState: Bool {
            switch runtimeSession.engine.session.connectionSubstate {
            case .failed, .disconnected:
                true
            case .awaitingServerHello, .awaitingFusionBegin, .inRound:
                false
            }
        }

        private func invalidateCovertOperations() {
            covertOperationGeneration &+= 1
        }

        private func invalidateHostOperations() {
            hostOperationGeneration &+= 1
        }

        private func handleCovertPreparedIfCurrent(
            plan: OpalFusion.Runtime.CovertPreparationPlan,
            generation: UInt64
        ) async {
            guard generation == covertOperationGeneration,
                  runtimeSession.covertSession.preparationPlan == plan else {
                return
            }

            await handle(.covertPrepared)
        }

        private func handleCovertPreparationFailureIfCurrent(
            summary: String,
            plan: OpalFusion.Runtime.CovertPreparationPlan,
            generation: UInt64
        ) async {
            guard generation == covertOperationGeneration,
                  runtimeSession.covertSession.preparationPlan == plan else {
                return
            }

            await handle(.covertPreparationFailed(summary: summary))
        }

        private func handleCovertResponseIfCurrent(
            _ responseBytes: [UInt8],
            request: OpalFusion.Runtime.CovertRequest,
            generation: UInt64
        ) async {
            guard generation == covertOperationGeneration,
                  runtimeSession.covertSession.outstandingRequest == request else {
                return
            }

            await handle(.receivedCovertResponseBytes(responseBytes))
        }

        private func handleCovertRequestFailureIfCurrent(
            summary: String,
            request: OpalFusion.Runtime.CovertRequest,
            generation: UInt64
        ) async {
            guard generation == covertOperationGeneration,
                  runtimeSession.covertSession.outstandingRequest == request else {
                return
            }

            await handle(.covertRequestFailed(summary: summary))
        }

        private func handleParticipantReservationLoadedIfCurrent(
            _ reservation: OpalFusion.Host.ParticipantReservation,
            roundIdentifier: OpalFusion.Round.Identifier,
            generation: UInt64
        ) async {
            guard isHostOperationCurrent(
                roundIdentifier: roundIdentifier,
                generation: generation
            ) else {
                Self.logger.debug(
                    "stale participant reservation ignored round=\(roundIdentifier.rawValue, privacy: .public)"
                )
                return
            }

            await handle(.participantReservationLoaded(reservation))
        }

        private func handleParticipantReservationRejectedIfCurrent(
            roundIdentifier: OpalFusion.Round.Identifier,
            generation: UInt64
        ) async {
            guard isHostOperationCurrent(
                roundIdentifier: roundIdentifier,
                generation: generation
            ) else {
                Self.logger.debug(
                    "stale participant reservation rejection ignored round=\(roundIdentifier.rawValue, privacy: .public)"
                )
                return
            }

            await handle(.participantReservationRejected)
        }

        private func handleFinalizedTransactionLoadedIfCurrent(
            _ transaction: OpalFusion.Host.FinalizedTransaction,
            roundIdentifier: OpalFusion.Round.Identifier,
            generation: UInt64
        ) async {
            guard isHostOperationCurrent(
                roundIdentifier: roundIdentifier,
                generation: generation
            ) else {
                Self.logger.debug(
                    "stale transaction finalization ignored round=\(roundIdentifier.rawValue, privacy: .public)"
                )
                return
            }

            await handle(.finalizedTransactionLoaded(transaction))
        }

        private func handleTransactionFinalizationRejectedIfCurrent(
            roundIdentifier: OpalFusion.Round.Identifier,
            generation: UInt64
        ) async {
            guard isHostOperationCurrent(
                roundIdentifier: roundIdentifier,
                generation: generation
            ) else {
                Self.logger.debug(
                    "stale transaction finalization rejection ignored round=\(roundIdentifier.rawValue, privacy: .public)"
                )
                return
            }

            await handle(.transactionFinalizationRejected)
        }

        private func isHostOperationCurrent(
            roundIdentifier: OpalFusion.Round.Identifier,
            generation: UInt64
        ) -> Bool {
            guard generation == hostOperationGeneration,
                  runtimeSession.engine.round?.identifier == roundIdentifier else {
                return false
            }

            return true
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
