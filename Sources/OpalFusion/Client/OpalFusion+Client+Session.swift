// OpalFusion+Client+Session.swift

import OpalDiagnostics

public extension OpalFusion.Client {
    actor Session {
        let configuration: OpalFusion.Client.Configuration
        let genesisHash: [UInt8]?
        let joinPools: OpalFusion.ProtocolModel.JoinPools
        let participantReservationSource: any OpalFusion.Host.ParticipantReservationSource
        let transactionAssembler: any OpalFusion.Host.TransactionAssembler
        let eventObserver: (any OpalFusion.Host.EventObserver)?
        let stateObserver: (any OpalFusion.Client.StateObserver)?
        let reconnectPolicy: OpalFusion.Client.ReconnectPolicy
        let dependencies: DependencyContext
        var runtimeDriver: OpalFusion.Runtime.LiveRuntimeDriver?
        var runtimeDriverGeneration: Int
        var isActive: Bool
        var retryAttempt: Int
        var pendingRetryTask: Task<Void, Never>?
        var lastEmittedSnapshot: OpalFusion.Client.Session.Snapshot

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
                .current
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



        public var currentSnapshot: OpalFusion.Client.Session.Snapshot {
            get async {
                if let runtimeDriver {
                    return OpalFusion.Client.Session.Snapshot(
                        runtimeSnapshot: await runtimeDriver.currentSnapshot
                    )
                }

                return lastEmittedSnapshot
            }
        }










    }
}

extension OpalFusion.Client.Session.Snapshot {
    init(runtimeSnapshot snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot) {
        self.init(
            state: snapshot.clientState,
            lastError: snapshot.lastError,
            lastErrorSummary: snapshot.lastErrorSummary,
            coordinatorStatus: snapshot.coordinatorStatus
        )
    }
}
