// OpalFusion+Client+Session.swift

import OpalDiagnostics

public extension OpalFusion.Client {
    /// Long-running CashFusion session authority for coordinator connection state and fusion round lifecycle.
    ///
    /// Wallet secrets, SwiftData snapshots, public chain transport, transaction broadcast, and generic wallet management stay behind host callbacks.
    actor Session {
        let configuration: OpalFusion.Client.Configuration
        let genesisHash: [UInt8]?
        let joinPools: OpalFusion.ProtocolModel.JoinPools
        let hostParticipantReservationSource: any OpalFusion.Host.ParticipantReservationSource
        let hostTransactionAssembler: any OpalFusion.Host.TransactionAssembler
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
            hostParticipantReservationSource: any OpalFusion.Host.ParticipantReservationSource,
            hostTransactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            stateObserver: (any OpalFusion.Client.StateObserver)? = nil,
            reconnectPolicy: OpalFusion.Client.ReconnectPolicy = .disabled
        ) {
            self.configuration = configuration
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.hostParticipantReservationSource = hostParticipantReservationSource
            self.hostTransactionAssembler = hostTransactionAssembler
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

        @available(
            *,
            deprecated,
            message: "Use init(configuration:genesisHash:joinPools:hostParticipantReservationSource:hostTransactionAssembler:eventObserver:stateObserver:reconnectPolicy:) to keep host-owned wallet boundaries explicit."
        )
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
            self.init(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                hostParticipantReservationSource: participantReservationSource,
                hostTransactionAssembler: transactionAssembler,
                eventObserver: eventObserver,
                stateObserver: stateObserver,
                reconnectPolicy: reconnectPolicy
            )
        }

        internal init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            hostParticipantReservationSource: any OpalFusion.Host.ParticipantReservationSource,
            hostTransactionAssembler: any OpalFusion.Host.TransactionAssembler,
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
            self.hostParticipantReservationSource = hostParticipantReservationSource
            self.hostTransactionAssembler = hostTransactionAssembler
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

        @available(
            *,
            deprecated,
            message: "Use the hostParticipantReservationSource and hostTransactionAssembler labels to keep host-owned wallet boundaries explicit."
        )
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
            self.init(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                hostParticipantReservationSource: participantReservationSource,
                hostTransactionAssembler: transactionAssembler,
                eventObserver: eventObserver,
                stateObserver: stateObserver,
                reconnectPolicy: reconnectPolicy,
                workflow: workflow,
                baseline: baseline,
                nowProvider: nowProvider,
                clockTickInterval: clockTickInterval,
                primaryTransportFactory: primaryTransportFactory,
                covertTransportFactory: covertTransportFactory,
                snapshotDeliveryHook: snapshotDeliveryHook
            )
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
