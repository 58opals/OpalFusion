// OpalFusion+Client+Session.swift

public extension OpalFusion.Client {
    actor Session {
        public struct Snapshot: Sendable, Equatable {
            public let state: OpalFusion.Client.State
            public let lastError: OpalFusion.Client.Error?
            public let lastErrorSummary: String?

            public init(
                state: OpalFusion.Client.State = .init(),
                lastError: OpalFusion.Client.Error? = nil,
                lastErrorSummary: String? = nil
            ) {
                self.state = state
                self.lastError = lastError
                self.lastErrorSummary = lastErrorSummary
            }
        }

        private struct Dependencies: Sendable {
            let workflow: OpalFusion.Execution.WorkflowContext?
            let baseline: OpalFusion.Transport.BaselineConfiguration
            let nowProvider: @Sendable () async -> OpalFusion.Execution.Instant
            let clockTickInterval: Duration
            let primaryTransportFactory: @Sendable () async -> (any OpalFusion.Runtime.PrimaryTransporting)?
            let covertTransportFactory: @Sendable () async -> (any OpalFusion.Runtime.CovertTransporting)?
            let snapshotDeliveryHook: @Sendable (
                OpalFusion.Client.Session.Snapshot
            ) async -> Void

            static let defaults = Self(
                workflow: nil,
                baseline: .electronCash443,
                nowProvider: { .now() },
                clockTickInterval: .milliseconds(250),
                primaryTransportFactory: { nil },
                covertTransportFactory: { nil },
                snapshotDeliveryHook: { _ in }
            )
        }

        private let configuration: OpalFusion.Client.Configuration
        private let genesisHash: [UInt8]?
        private let joinPools: OpalFusion.ProtocolModel.JoinPools
        private let participantReservationSource: any OpalFusion.Host.ParticipantReservationSource
        private let transactionAssembler: any OpalFusion.Host.TransactionAssembler
        private let eventObserver: (any OpalFusion.Host.EventObserver)?
        private let stateObserver: (any OpalFusion.Client.StateObserver)?
        private let dependencies: Dependencies
        private var runtimeDriver: OpalFusion.Runtime.LiveRuntimeDriver?
        private var runtimeDriverGeneration: Int
        private var lastEmittedSnapshot: OpalFusion.Client.Session.Snapshot

        public init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            participantReservationSource: any OpalFusion.Host.ParticipantReservationSource,
            transactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            stateObserver: (any OpalFusion.Client.StateObserver)? = nil
        ) {
            self.configuration = configuration
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.participantReservationSource = participantReservationSource
            self.transactionAssembler = transactionAssembler
            self.eventObserver = eventObserver
            self.stateObserver = stateObserver
            self.dependencies = .defaults
            self.runtimeDriver = nil
            self.runtimeDriverGeneration = 0
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
            self.lastEmittedSnapshot = .init()
        }

        public func start() async {
            guard runtimeDriver == nil else {
                return
            }

            await updateSnapshotIfNeeded(.init())

            runtimeDriverGeneration += 1
            let runtimeDriverGeneration = self.runtimeDriverGeneration
            let runtimeDriver = await makeRuntimeDriver(
                generation: runtimeDriverGeneration
            )
            self.runtimeDriver = runtimeDriver

            await runtimeDriver.start()
            let snapshot = OpalFusion.Client.Session.Snapshot(
                await runtimeDriver.snapshot()
            )
            await updateSnapshotIfNeeded(snapshot)

            if snapshot.state.isConnected == false,
               snapshot.lastError != nil,
               self.runtimeDriver === runtimeDriver,
               self.runtimeDriverGeneration == runtimeDriverGeneration {
                self.runtimeDriver = nil
            }
        }

        public func stop() async {
            guard let runtimeDriver else {
                return
            }

            await runtimeDriver.stop()
            self.runtimeDriver = nil
            runtimeDriverGeneration += 1
        }

        public func snapshot() async -> OpalFusion.Client.Session.Snapshot {
            if let runtimeDriver {
                return OpalFusion.Client.Session.Snapshot(
                    await runtimeDriver.snapshot()
                )
            }

            return lastEmittedSnapshot
        }

        private func makeRuntimeDriver(
            generation: Int
        ) async -> OpalFusion.Runtime.LiveRuntimeDriver {
            let primaryTransport = await dependencies.primaryTransportFactory()
            let covertTransport = await dependencies.covertTransportFactory()
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
                primaryTransport: primaryTransport,
                covertTransport: covertTransport
            )
        }

        private func receive(
            _ snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot,
            generation: Int
        ) async {
            guard generation == runtimeDriverGeneration else {
                return
            }

            let sessionSnapshot = OpalFusion.Client.Session.Snapshot(snapshot)
            await dependencies.snapshotDeliveryHook(sessionSnapshot)
            await updateSnapshotIfNeeded(sessionSnapshot)

            if sessionSnapshot.state.isConnected == false,
               sessionSnapshot.lastError != nil {
                runtimeDriver = nil
            }
        }

        private func updateSnapshotIfNeeded(
            _ snapshot: OpalFusion.Client.Session.Snapshot
        ) async {
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
            lastErrorSummary: snapshot.lastErrorSummary
        )
    }
}
