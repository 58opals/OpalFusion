// OpalFusion+Runtime+LiveRuntimeDriver.swift

import Foundation

extension OpalFusion.Runtime {
    actor LiveRuntimeDriver {
        typealias SnapshotSink = @Sendable (
            OpalFusion.Runtime.LiveRuntimeDriver.Snapshot
        ) async -> Void
        typealias HostEventSink = @Sendable (
            OpalFusion.Round.Identifier?,
            OpalFusion.Host.Event
        ) async -> Void
        typealias PrimaryTransportBuilder = @Sendable (
            OpalFusion.Client.Configuration
        ) async -> any OpalFusion.Runtime.PrimaryTransporting
        typealias CovertTransportBuilder = @Sendable (
            OpalFusion.Client.Configuration
        ) async -> any OpalFusion.Runtime.CovertTransporting

        private let configuration: OpalFusion.Client.Configuration
        private var runtimeSession: OpalFusion.Runtime.PrimaryRuntimeSession
        private let participantReservationSource: any OpalFusion.Host.ParticipantReservationSource
        private let transactionAssembler: any OpalFusion.Host.TransactionAssembler
        private let eventObserver: (any OpalFusion.Host.EventObserver)?
        private let hostEventSink: HostEventSink
        private let snapshotSink: SnapshotSink
        private let primaryTransportFactory: PrimaryTransportBuilder
        private let covertTransportFactory: CovertTransportBuilder
        private var primaryTransport: (any OpalFusion.Runtime.PrimaryTransporting)?
        private var covertTransport: (any OpalFusion.Runtime.CovertTransporting)?
        private let nowProvider: @Sendable () async -> OpalFusion.Execution.Instant
        private let clockTickInterval: Duration
        private var primaryReadTask: Task<Void, Never>?
        private var clockTask: Task<Void, Never>?
        private var covertPreparationTask: Task<Void, Never>?
        private var covertRequestTask: Task<Void, Never>?
        private var participantReservationTask: Task<Void, Never>?
        private var transactionFinalizationTask: Task<Void, Never>?
        private var isRunning: Bool
        private var lastEmittedSnapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot?
        private var lastFailureAllowsReconnect: Bool
        private var stopRequested: Bool

        init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            workflow: OpalFusion.Execution.WorkflowContext? = nil,
            participantReservationSource: any OpalFusion.Host.ParticipantReservationSource,
            transactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            hostEventSink: @escaping HostEventSink = { _, _ in },
            snapshotSink: @escaping SnapshotSink = { _ in },
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443,
            nowProvider: @escaping @Sendable () async -> OpalFusion.Execution.Instant = {
                .now()
            },
            clockTickInterval: Duration = .milliseconds(250),
            primaryTransportFactory: PrimaryTransportBuilder? = nil,
            covertTransportFactory: CovertTransportBuilder? = nil,
            primaryTransport: (any OpalFusion.Runtime.PrimaryTransporting)? = nil,
            covertTransport: (any OpalFusion.Runtime.CovertTransporting)? = nil
        ) {
            self.configuration = configuration
            self.runtimeSession = .init(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                workflow: workflow,
                baseline: baseline
            )
            self.participantReservationSource = participantReservationSource
            self.transactionAssembler = transactionAssembler
            self.eventObserver = eventObserver
            self.hostEventSink = hostEventSink
            self.snapshotSink = snapshotSink
            if let primaryTransport {
                self.primaryTransportFactory = { _ in
                    primaryTransport
                }
            } else if let primaryTransportFactory {
                self.primaryTransportFactory = primaryTransportFactory
            } else {
                self.primaryTransportFactory = { configuration in
                    OpalFusion.Runtime.LivePrimaryTransport(
                        host: configuration.coordinatorHost,
                        port: configuration.coordinatorPort,
                        requiresTLS: configuration.coordinatorRequiresTLS
                    )
                }
            }
            if let covertTransport {
                self.covertTransportFactory = { _ in
                    covertTransport
                }
            } else if let covertTransportFactory {
                self.covertTransportFactory = covertTransportFactory
            } else {
                self.covertTransportFactory = { configuration in
                    OpalFusion.Runtime.LiveCovertTransport(
                        torSocks5: configuration.torSocks5
                    )
                }
            }
            self.primaryTransport = nil
            self.covertTransport = nil
            self.nowProvider = nowProvider
            self.clockTickInterval = clockTickInterval
            self.primaryReadTask = nil
            self.clockTask = nil
            self.covertPreparationTask = nil
            self.covertRequestTask = nil
            self.participantReservationTask = nil
            self.transactionFinalizationTask = nil
            self.isRunning = false
            self.lastEmittedSnapshot = nil
            self.lastFailureAllowsReconnect = false
            self.stopRequested = false
        }

        func start() async {
            guard isRunning == false else {
                return
            }
            isRunning = true
            stopRequested = false
            lastFailureAllowsReconnect = false

            if let summary = OpalFusion.Runtime.validateStartupConfiguration(
                runtimeSession.engine.session.configuration,
                genesisHash: runtimeSession.engine.session.genesisHash,
                joinPools: runtimeSession.engine.session.joinPools
            ) {
                await handle(.invalidConfiguration(summary: summary))
                await tearDownTransports()
                return
            }

            if primaryTransport == nil {
                primaryTransport = await primaryTransportFactory(configuration)
            }
            if covertTransport == nil {
                covertTransport = await covertTransportFactory(configuration)
            }

            guard let primaryTransport else {
                await handle(
                    .primaryTransportFailed(
                        summary: "Primary transport was unavailable"
                    )
                )
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
                if stopRequested,
                   Self.shouldIgnorePrimaryTransportCancellation(error) {
                    return
                }

                OpalFusionDiagnostics.record(
                    OpalFusionDiagnostics.Event.primaryConnectFailed,
                    category: OpalFusionDiagnostics.Category.primary,
                    fields: [
                        OpalFusionDiagnostics.operationField("primary_connect")
                    ] + OpalFusionDiagnostics.errorFields(error)
                )
                await handle(
                    .primaryTransportFailed(
                        summary: "Primary connection failed"
                    )
                )
                await tearDownTransports()
            }
        }

        func stop() async {
            guard isRunning else {
                return
            }

            stopRequested = true
            await handle(.stopped)
        }

        func snapshot() -> OpalFusion.Runtime.LiveRuntimeDriver.Snapshot {
            let diagnostics = runtimeSession.diagnostics(
                activity: diagnosticActivity
            )
            return .init(
                clientState: runtimeSession.clientState,
                lastError: runtimeSession.lastError,
                lastErrorSummary: runtimeSession.lastErrorSummary,
                diagnostics: diagnostics,
                coordinatorStatus: runtimeSession.coordinatorStatus,
                allowsReconnect: lastFailureAllowsReconnect
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
                    guard Task.isCancelled == false else {
                        return
                    }
                    self.logPreRoundDisconnectIfNeeded()
                    await self.handle(.disconnected)
                } catch {
                    guard Task.isCancelled == false,
                          Self.shouldIgnorePrimaryTransportCancellation(error) == false else {
                        return
                    }
                    OpalFusionDiagnostics.record(
                        OpalFusionDiagnostics.Event.transportError,
                        category: OpalFusionDiagnostics.Category.transport,
                        fields: [
                            OpalFusionDiagnostics.operationField("primary_read")
                        ] + OpalFusionDiagnostics.errorFields(error)
                    )
                    await self.handle(
                        .primaryTransportFailed(
                            summary: "Primary read failed"
                        )
                    )
                }
            }
        }

        private static func shouldIgnorePrimaryTransportCancellation(
            _ error: Error
        ) -> Bool {
            if error is CancellationError {
                return true
            }

            if let transportError = error as? OpalFusion.Runtime.LiveTransportError,
               transportError == .primaryConnectionCancelled {
                return true
            }

            let nsError = error as NSError
            if nsError.domain == NSPOSIXErrorDomain,
               nsError.code == Int(ECANCELED) {
                return true
            }

            if nsError.domain == NSURLErrorDomain,
               nsError.code == NSURLErrorCancelled {
                return true
            }

            return false
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
            let failureAllowsReconnect = canReconnectAfter(input)
            let effects = runtimeSession.apply(
                input: input,
                now: await nowProvider()
            )

            for effect in effects {
                await process(effect)

                if hasTerminalConnectionState {
                    break
                }
            }

            let shouldCancelRoundScopedTasks = runtimeSession.engine.session.connectionSubstate != .inRound
            let reachedTerminalConnectionState = hasTerminalConnectionState
            let shouldProjectPreRoundDisconnect = reachedTerminalConnectionState &&
                runtimeSession.engine.round == nil &&
                runtimeSession.clientState.isConnected

            if shouldCancelRoundScopedTasks {
                cancelCovertTasks()
                cancelHostTasks()
                if let covertTransport {
                    await covertTransport.reset()
                }
            }

            if reachedTerminalConnectionState {
                lastFailureAllowsReconnect = lastFailureAllowsReconnect ||
                    (
                        failureAllowsReconnect &&
                            runtimeSession.lastError == .transportUnavailable
                    )
                await emitSnapshotIfNeeded()
                await tearDownTransports()
                if shouldProjectPreRoundDisconnect {
                    await handle(.disconnected)
                }
                return
            }

            lastFailureAllowsReconnect = false
            await emitSnapshotIfNeeded()
        }

        private func process(
            _ effect: OpalFusion.Runtime.PrimaryRuntimeSession.Effect
        ) async {
            switch effect {
            case let .writePrimaryBytes(bytes):
                guard let primaryTransport else {
                    await handle(
                        .primaryTransportFailed(
                            summary: "Primary transport was unavailable"
                        )
                    )
                    return
                }
                do {
                    try await primaryTransport.write(bytes)
                    runtimeSession.recordWrittenPrimaryFrame(bytes)
                } catch {
                    OpalFusionDiagnostics.record(
                        OpalFusionDiagnostics.Event.transportError,
                        category: OpalFusionDiagnostics.Category.transport,
                        traceID: OpalFusionDiagnostics.makeTraceID(
                            for: runtimeSession.engine.round?.identifier
                        ),
                        fields: [
                            OpalFusionDiagnostics.operationField("primary_write"),
                            OpalFusionDiagnostics.frameByteCountField(bytes.count)
                        ] + OpalFusionDiagnostics.errorFields(error)
                    )
                    await handle(
                        .primaryTransportFailed(
                            summary: "Primary write failed"
                        )
                    )
                }
            case let .prepareCovertEndpoint(plan):
                guard let covertTransport else {
                    return
                }
                covertPreparationTask?.cancel()
                covertPreparationTask = Task { [covertTransport] in
                    do {
                        try await covertTransport.prepare(plan)
                        guard Task.isCancelled == false else {
                            return
                        }
                        await self.handleCovertPreparedIfCurrent(plan: plan)
                    } catch {
                        guard Task.isCancelled == false else {
                            return
                        }
                        OpalFusionDiagnostics.record(
                            OpalFusionDiagnostics.Event.covertPrepareFailed,
                            category: OpalFusionDiagnostics.Category.covert,
                            traceID: OpalFusionDiagnostics.makeTraceID(
                                for: plan.endpoint.roundIdentifier
                            ),
                            fields: [
                                OpalFusionDiagnostics.operationField("covert_prepare")
                            ] + OpalFusionDiagnostics.errorFields(error)
                        )
                        await self.handleCovertPreparationFailureIfCurrent(
                            summary: "Covert endpoint preparation failed",
                            plan: plan
                        )
                    }
                }
            case let .performCovertRequest(request):
                guard let covertTransport else {
                    return
                }
                covertRequestTask?.cancel()
                covertRequestTask = Task { [covertTransport] in
                    do {
                        let responseBytes = try await covertTransport.perform(request)
                        guard Task.isCancelled == false else {
                            return
                        }
                        await self.handleCovertResponseIfCurrent(
                            responseBytes,
                            request: request
                        )
                    } catch {
                        guard Task.isCancelled == false else {
                            return
                        }
                        OpalFusionDiagnostics.record(
                            OpalFusionDiagnostics.Event.covertRequestFailed,
                            category: OpalFusionDiagnostics.Category.covert,
                            traceID: OpalFusionDiagnostics.makeTraceID(
                                for: request.endpoint.roundIdentifier
                            ),
                            fields: [
                                OpalFusionDiagnostics.operationField("covert_request"),
                                OpalFusionDiagnostics.payloadByteCountField(
                                    request.payload.count
                                )
                            ] + OpalFusionDiagnostics.errorFields(error)
                        )
                        await self.handleCovertRequestFailureIfCurrent(
                            summary: "Covert request failed",
                            request: request
                        )
                    }
                }
            case let .requestParticipantReservation(context):
                let participantReservationSource = self.participantReservationSource
                let roundIdentifier = context.roundIdentifier
                participantReservationTask?.cancel()
                participantReservationTask = Task { [participantReservationSource] in
                    do {
                        let reservation = try await participantReservationSource.participantReservation(
                            for: context
                        )
                        guard Task.isCancelled == false else {
                            return
                        }
                        await self.handleHostOperationIfCurrent(
                            roundIdentifier: roundIdentifier,
                            staleOperation: "participant reservation",
                            input: .participantReservationLoaded(reservation)
                        )
                    } catch {
                        guard Task.isCancelled == false else {
                            return
                        }
                        await self.handleHostOperationIfCurrent(
                            roundIdentifier: roundIdentifier,
                            staleOperation: "participant reservation rejection",
                            input: .participantReservationRejected
                        )
                    }
                }
            case let .requestTransactionFinalization(roundIdentifier, proposal):
                let transactionAssembler = self.transactionAssembler
                transactionFinalizationTask?.cancel()
                transactionFinalizationTask = Task { [transactionAssembler] in
                    do {
                        let transaction = try await transactionAssembler.finalizeTransaction(
                            for: roundIdentifier,
                            proposal: proposal
                        )
                        guard Task.isCancelled == false else {
                            return
                        }
                        await self.handleHostOperationIfCurrent(
                            roundIdentifier: roundIdentifier,
                            staleOperation: "transaction finalization",
                            input: .finalizedTransactionLoaded(transaction)
                        )
                    } catch let failure as OpalFusion.Host.TransactionFinalizationFailure {
                        guard Task.isCancelled == false else {
                            return
                        }
                        await self.handleHostOperationIfCurrent(
                            roundIdentifier: roundIdentifier,
                            staleOperation: "transaction finalization rejection",
                            input: .transactionFinalizationRejected(failure)
                        )
                    } catch {
                        guard Task.isCancelled == false else {
                            return
                        }
                        await self.handleHostOperationIfCurrent(
                            roundIdentifier: roundIdentifier,
                            staleOperation: "transaction finalization rejection",
                            input: .transactionFinalizationRejected(
                                .transactionAssemblyFailed(
                                    summary: "Host transaction finalization failed"
                                )
                            )
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
            cancelCovertTasks()
            cancelHostTasks()
            primaryReadTask?.cancel()
            primaryReadTask = nil
            clockTask?.cancel()
            clockTask = nil
            if let primaryTransport {
                await primaryTransport.close()
                self.primaryTransport = nil
            }
            if let covertTransport {
                await covertTransport.reset()
                self.covertTransport = nil
            }
        }

        private var hasTerminalConnectionState: Bool {
            switch runtimeSession.engine.session.connectionSubstate {
            case .failed, .disconnected:
                true
            case .awaitingServerHello, .awaitingFusionBegin, .inRound:
                false
            }
        }

        private var diagnosticActivity: OpalFusion.Client.Diagnostics.Activity {
            if stopRequested {
                return .stopped
            }

            if runtimeSession.lastError != nil {
                return .failed
            }

            if runtimeSession.clientState.isConnected {
                return .running
            }

            if isRunning {
                return .connecting
            }

            return .idle
        }

        private func canReconnectAfter(
            _ input: OpalFusion.Runtime.PrimaryRuntimeSession.Input
        ) -> Bool {
            guard runtimeSession.engine.round == nil else {
                return false
            }

            return switch input {
            case .disconnected, .primaryTransportFailed:
                true
            default:
                false
            }
        }

        private func cancelCovertTasks() {
            covertPreparationTask?.cancel()
            covertPreparationTask = nil
            covertRequestTask?.cancel()
            covertRequestTask = nil
        }

        private func cancelHostTasks() {
            participantReservationTask?.cancel()
            participantReservationTask = nil
            transactionFinalizationTask?.cancel()
            transactionFinalizationTask = nil
        }

        private func handleCovertPreparedIfCurrent(
            plan: OpalFusion.Runtime.CovertPreparationPlan
        ) async {
            guard runtimeSession.covertSession.preparationPlan == plan else {
                return
            }

            await handle(.covertPrepared)
        }

        private func handleCovertPreparationFailureIfCurrent(
            summary: String,
            plan: OpalFusion.Runtime.CovertPreparationPlan
        ) async {
            guard runtimeSession.covertSession.preparationPlan == plan else {
                return
            }

            await handle(.covertPreparationFailed(summary: summary))
        }

        private func handleCovertResponseIfCurrent(
            _ responseBytes: [UInt8],
            request: OpalFusion.Runtime.CovertRequest
        ) async {
            guard runtimeSession.covertSession.outstandingRequest == request else {
                return
            }

            await handle(.receivedCovertResponseBytes(responseBytes))
        }

        private func handleCovertRequestFailureIfCurrent(
            summary: String,
            request: OpalFusion.Runtime.CovertRequest
        ) async {
            guard runtimeSession.covertSession.outstandingRequest == request else {
                return
            }

            await handle(.covertRequestFailed(summary: summary))
        }

        private func handleHostOperationIfCurrent(
            roundIdentifier: OpalFusion.Round.Identifier,
            staleOperation: String,
            input: OpalFusion.Runtime.PrimaryRuntimeSession.Input
        ) async {
            guard runtimeSession.engine.round?.identifier == roundIdentifier else {
                OpalFusionDiagnostics.record(
                    OpalFusionDiagnostics.Event.roundProgressed,
                    category: OpalFusionDiagnostics.Category.round,
                    traceID: OpalFusionDiagnostics.makeTraceID(for: roundIdentifier),
                    fields: [
                        OpalFusionDiagnostics.operationField("stale_host_operation"),
                        OpalFusionDiagnostics.publicField("phase", staleOperation)
                    ]
                )
                return
            }

            await handle(input)
        }

        private func emitSnapshotIfNeeded() async {
            let snapshot = snapshot()
            guard snapshot != lastEmittedSnapshot else {
                return
            }

            lastEmittedSnapshot = snapshot
            await snapshotSink(snapshot)
        }

        private func logPreRoundDisconnectIfNeeded() {
            let trace = runtimeSession.preRoundTrace
            guard runtimeSession.engine.round == nil,
                  trace.wroteClientHello || trace.wroteJoinPools || trace.lastInboundKind != nil else {
                return
            }

            var fields = [
                OpalFusionDiagnostics.operationField("primary_preround_disconnect"),
                OpalFusionDiagnostics.publicField(
                    "message_kind",
                    trace.lastInboundKind?.rawValue ?? "nil"
                ),
                OpalFusionDiagnostics.publicField(
                    "phase",
                    trace.handshakeStage.rawValue
                )
            ]
            if let payloadByteCount = trace.lastInboundPayloadBytes {
                fields.append(
                    OpalFusionDiagnostics.payloadByteCountField(payloadByteCount)
                )
            }
            OpalFusionDiagnostics.record(
                OpalFusionDiagnostics.Event.primaryConnectionPeerEOF,
                category: OpalFusionDiagnostics.Category.primary,
                fields: fields
            )
        }
    }
}
