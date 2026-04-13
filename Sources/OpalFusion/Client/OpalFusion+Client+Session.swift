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
            let nowProvider: @Sendable () -> OpalFusion.Execution.Instant
            let clockTickInterval: Duration
            let primaryTransportFactory: @Sendable () -> (any OpalFusion.Runtime.PrimaryTransporting)?
            let covertTransportFactory: @Sendable () -> (any OpalFusion.Runtime.CovertTransporting)?

            static let defaults = Self(
                workflow: nil,
                baseline: .electronCash443,
                nowProvider: { .now() },
                clockTickInterval: .milliseconds(250),
                primaryTransportFactory: { nil },
                covertTransportFactory: { nil }
            )
        }

        private let configuration: OpalFusion.Client.Configuration
        private let genesisHash: [UInt8]?
        private let joinPools: OpalFusion.ProtocolModel.JoinPools
        private let participantInputProvider: any OpalFusion.Host.ParticipantInputProvider
        private let transactionAssembler: any OpalFusion.Host.TransactionAssembler
        private let eventObserver: (any OpalFusion.Host.EventObserver)?
        private let stateObserver: (any OpalFusion.Client.StateObserver)?
        private let dependencies: Dependencies
        private var runtimeDriver: OpalFusion.Runtime.LiveRuntimeDriver?
        private var lastSnapshot: OpalFusion.Client.Session.Snapshot

        public init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            participantInputProvider: any OpalFusion.Host.ParticipantInputProvider,
            transactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            stateObserver: (any OpalFusion.Client.StateObserver)? = nil
        ) {
            self.configuration = configuration
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.participantInputProvider = participantInputProvider
            self.transactionAssembler = transactionAssembler
            self.eventObserver = eventObserver
            self.stateObserver = stateObserver
            self.dependencies = .defaults
            self.runtimeDriver = nil
            self.lastSnapshot = .init()
        }

        internal init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            participantInputProvider: any OpalFusion.Host.ParticipantInputProvider,
            transactionAssembler: any OpalFusion.Host.TransactionAssembler,
            eventObserver: (any OpalFusion.Host.EventObserver)? = nil,
            stateObserver: (any OpalFusion.Client.StateObserver)? = nil,
            workflow: OpalFusion.Execution.WorkflowContext? = nil,
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443,
            nowProvider: @escaping @Sendable () -> OpalFusion.Execution.Instant = {
                .now()
            },
            clockTickInterval: Duration = .milliseconds(250),
            primaryTransportFactory: @escaping @Sendable () -> (any OpalFusion.Runtime.PrimaryTransporting)? = { nil },
            covertTransportFactory: @escaping @Sendable () -> (any OpalFusion.Runtime.CovertTransporting)? = { nil }
        ) {
            self.configuration = configuration
            self.genesisHash = genesisHash
            self.joinPools = joinPools
            self.participantInputProvider = participantInputProvider
            self.transactionAssembler = transactionAssembler
            self.eventObserver = eventObserver
            self.stateObserver = stateObserver
            self.dependencies = .init(
                workflow: workflow,
                baseline: baseline,
                nowProvider: nowProvider,
                clockTickInterval: clockTickInterval,
                primaryTransportFactory: primaryTransportFactory,
                covertTransportFactory: covertTransportFactory
            )
            self.runtimeDriver = nil
            self.lastSnapshot = .init()
        }

        public func start() async {
            guard runtimeDriver == nil else {
                return
            }

            await updateSnapshotIfNeeded(.init())

            let runtimeDriver = makeRuntimeDriver()
            self.runtimeDriver = runtimeDriver

            await runtimeDriver.start()
            await updateSnapshotIfNeeded(.init(await runtimeDriver.snapshot()))
        }

        public func stop() async {
            guard let runtimeDriver else {
                return
            }

            await runtimeDriver.stop()
            self.runtimeDriver = nil
        }

        public func snapshot() async -> OpalFusion.Client.Session.Snapshot {
            if let runtimeDriver {
                let snapshot = OpalFusion.Client.Session.Snapshot(
                    await runtimeDriver.snapshot()
                )
                lastSnapshot = snapshot
                return snapshot
            }

            return lastSnapshot
        }

        private func makeRuntimeDriver() -> OpalFusion.Runtime.LiveRuntimeDriver {
            OpalFusion.Runtime.LiveRuntimeDriver(
                configuration: configuration,
                genesisHash: genesisHash,
                joinPools: joinPools,
                workflow: dependencies.workflow,
                participantInputProvider: participantInputProvider,
                transactionAssembler: transactionAssembler,
                eventObserver: eventObserver,
                snapshotSink: { snapshot in
                    await self.receive(snapshot)
                },
                baseline: dependencies.baseline,
                nowProvider: dependencies.nowProvider,
                clockTickInterval: dependencies.clockTickInterval,
                primaryTransport: dependencies.primaryTransportFactory(),
                covertTransport: dependencies.covertTransportFactory()
            )
        }

        private func receive(
            _ snapshot: OpalFusion.Runtime.LiveRuntimeDriver.Snapshot
        ) async {
            await updateSnapshotIfNeeded(.init(snapshot))
        }

        private func updateSnapshotIfNeeded(
            _ snapshot: OpalFusion.Client.Session.Snapshot
        ) async {
            guard snapshot != lastSnapshot else {
                return
            }

            lastSnapshot = snapshot
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
