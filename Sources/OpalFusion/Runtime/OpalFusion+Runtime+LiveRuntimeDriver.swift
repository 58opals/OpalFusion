// OpalFusion+Runtime+LiveRuntimeDriver.swift

import Foundation
import OpalDiagnostics

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

        let configuration: OpalFusion.Client.Configuration
        var runtimeSession: OpalFusion.Runtime.PrimaryRuntimeSession
        let participantReservationSource: any OpalFusion.Host.ParticipantReservationSource
        let transactionAssembler: any OpalFusion.Host.TransactionAssembler
        let eventObserver: (any OpalFusion.Host.EventObserver)?
        let hostEventSink: HostEventSink
        let snapshotSink: SnapshotSink
        let primaryTransportFactory: PrimaryTransportBuilder
        let covertTransportFactory: CovertTransportBuilder
        var primaryTransport: (any OpalFusion.Runtime.PrimaryTransporting)?
        var covertTransport: (any OpalFusion.Runtime.CovertTransporting)?
        let nowProvider: @Sendable () async -> OpalFusion.Execution.Instant
        let clockTickInterval: Duration
        var primaryReadTask: Task<Void, Never>?
        var clockTask: Task<Void, Never>?
        var covertPreparationTask: Task<Void, Never>?
        var covertRequestTask: Task<Void, Never>?
        var participantReservationTask: Task<Void, Never>?
        var transactionFinalizationTask: Task<Void, Never>?
        var isRunning: Bool
        var lastEmittedSnapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot?
        var lastFailureAllowsReconnect: Bool
        var stopRequested: Bool

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
                .current
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



        var currentSnapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot {
            .init(
                clientState: runtimeSession.clientState,
                lastError: runtimeSession.lastError,
                lastErrorSummary: runtimeSession.lastErrorSummary,
                coordinatorStatus: runtimeSession.coordinatorStatus,
                allowsReconnect: lastFailureAllowsReconnect
            )
        }









        var hasTerminalConnectionState: Bool {
            switch runtimeSession.engine.session.connectionSubstate {
            case .failed, .disconnected:
                true
            case .awaitingServerHello, .awaitingFusionBegin, .inRound:
                false
            }
        }












        var preRoundHandshakePhase: String {
            switch runtimeSession.engine.session.connectionSubstate {
            case .awaitingServerHello:
                "awaitingServerHello"
            case .awaitingFusionBegin:
                "awaitingFusionBegin"
            case .inRound:
                "inRound"
            case .disconnected, .failed:
                "notStarted"
            }
        }
    }
}
