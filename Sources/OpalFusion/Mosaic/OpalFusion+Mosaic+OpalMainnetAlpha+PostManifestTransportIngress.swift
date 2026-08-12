// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestTransportIngress.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Owns authenticated NIP-59 admission into one post-manifest role driver.
    ///
    /// Relay fan-in, recipient-key generation or persistence, Tor, reconnect, and publication
    /// remain outside this actor. Callers submit only a signed gift wrap; this ingress selects its
    /// attempt-scoped decryption authority and installs one write-ahead admission journal before
    /// runtime admission. A restored nonempty journal fails closed until full runtime recovery is
    /// available.
    actor PostManifestTransportIngress {
        private enum StartupDisposition {
            case stop
            case inputSourceTerminated(InputSourceTermination)
        }

        private let driver: Driver
        private let recipientSet: RecipientSet
        private let dependencies: Dependencies
        private var startupDisposition: StartupDisposition?

        private(set) var state: State = .idle

        init(
            claimedRuntimeConstruction: AttemptTransportOwner
                .InboundRuntimeProvisioning.ClaimedRuntimeConstruction,
            bootstrap: Driver.Bootstrap,
            roleDependencies: Driver.RoleDependencies,
            recipientSet: RecipientSet,
            dependencies: Dependencies
        ) throws(InitializationError) {
            let admissionJournal: AdmissionJournal
            do {
                admissionJournal = try .init(
                    context: .init(
                        bootstrap: bootstrap,
                        recipientBindings: recipientSet.recipientBindings
                    ),
                    store: dependencies.admissionJournalStore
                )
            } catch let error {
                throw .admissionJournal(error)
            }
            guard !admissionJournal.requiresRuntimeRecovery else {
                throw .runtimeRecoveryRequired
            }
            do {
                driver = try Driver(
                    claimedRuntimeConstruction: claimedRuntimeConstruction,
                    bootstrap: bootstrap,
                    dependencies: roleDependencies,
                    admissionJournal: admissionJournal
                )
            } catch let error {
                throw .runtimeDriver(error)
            }
            self.recipientSet = recipientSet
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
            _ giftWrap: OpalFusion.Mosaic.NostrNamespace.Event
        ) async -> Decision {
            guard state == .running else {
                return .rejected(.notRunning)
            }

            let recipientIdentity: Data
            do {
                recipientIdentity = try Transport.recipientEventIdentity(
                    in: giftWrap
                )
            } catch let failure {
                return .rejected(.transport(failure))
            }
            guard let recipient = recipientSet.capability(
                for: recipientIdentity
            ) else {
                return .rejected(.unknownRecipient)
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
