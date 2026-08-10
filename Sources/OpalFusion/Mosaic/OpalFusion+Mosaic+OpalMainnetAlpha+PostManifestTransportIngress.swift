// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestTransportIngress.swift

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Owns authenticated NIP-59 admission into one post-manifest role driver.
    ///
    /// Relay fan-in, recipient-key storage, Tor, reconnect, publication, and durable
    /// replay remain outside this actor. Callers cannot submit a preconstructed runtime fact.
    actor PostManifestTransportIngress {
        private enum StartupDisposition {
            case stop
            case inputSourceTerminated(InputSourceTermination)
        }

        private let driver: Driver
        private let dependencies: Dependencies
        private var startupDisposition: StartupDisposition?

        private(set) var state: State = .idle

        init(
            bootstrap: Driver.Bootstrap,
            roleDependencies: Driver.RoleDependencies,
            dependencies: Dependencies
        ) throws(InitializationError) {
            do {
                driver = try Driver(
                    bootstrap: bootstrap,
                    dependencies: roleDependencies
                )
            } catch let error {
                throw .runtimeDriver(error)
            }
            self.dependencies = dependencies
        }

        func start() async -> Bool {
            guard state == .idle else { return false }
            state = .starting
            await dependencies.beforeDriverStart()
            await driver.start()
            let disposition = startupDisposition
            startupDisposition = nil
            switch disposition {
            case nil:
                state = .running
            case .stop:
                state = .stopping
                await driver.stop()
            case let .inputSourceTerminated(termination):
                state = .stopping
                _ = await driver.inputSourceDidTerminate(termination)
            }
            return true
        }

        func submit(
            _ giftWrap: OpalFusion.Mosaic.NostrNamespace.Event,
            to recipient: Transport.RecipientCapability
        ) async -> Decision {
            guard state == .running else {
                return .rejected(.notRunning)
            }
            do {
                guard try await driver.submit(
                    giftWrap,
                    to: recipient,
                    currentUnixSeconds: dependencies.currentUnixSeconds()
                ) else {
                    return .rejected(.runtimeRejected)
                }
            } catch let failure {
                return .rejected(.transport(failure))
            }
            return .accepted
        }

        func inputSourceDidTerminate(
            _ termination: InputSourceTermination
        ) async -> Bool {
            switch state {
            case .starting:
                guard startupDisposition == nil else { return false }
                startupDisposition = .inputSourceTerminated(termination)
                return true
            case .running:
                state = .stopping
                return await driver.inputSourceDidTerminate(termination)
            case .idle, .stopping, .terminal:
                return false
            }
        }

        func stop() async {
            switch state {
            case .starting:
                guard startupDisposition == nil else { return }
                startupDisposition = .stop
            case .running:
                state = .stopping
                await driver.stop()
            case .idle, .stopping, .terminal:
                return
            }
        }

        @discardableResult
        func waitForTermination() async -> Driver.State? {
            switch state {
            case .idle:
                return nil
            case .starting:
                return nil
            case .running, .stopping:
                let terminalState = await driver.waitForTermination()
                state = .terminal(terminalState)
                return terminalState
            case let .terminal(terminalState):
                return terminalState
            }
        }

    }
}
