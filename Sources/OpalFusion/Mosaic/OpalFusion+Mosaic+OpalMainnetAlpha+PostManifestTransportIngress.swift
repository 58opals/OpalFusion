// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestTransportIngress.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// Owns authenticated NIP-59 admission into one post-manifest role driver.
    ///
    /// Relay fan-in, recipient-key generation or persistence, Tor, reconnect, and publication
    /// remain outside this actor. Callers submit only a signed gift wrap; this ingress selects its
    /// attempt-scoped decryption authority and installs one write-ahead admission journal before
    /// runtime admission. A restored nonempty journal can resume only by replaying the exact
    /// authenticated gift wraps into a newly supplied, exactly bound runtime construction.
    actor PostManifestTransportIngress {
        private enum StartupDisposition {
            case stop
            case inputSourceTerminated(InputSourceTermination)
        }

        private let driver: Driver
        private let recipientSet: RecipientSet
        private let dependencies: Dependencies
        private let admissionJournal: AdmissionJournal
        private let recoveredAdmissions: [(
            event: OpalFusion.Mosaic.NostrNamespace.Event,
            source: RecoveredAdmission
        )]
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
            let recoveredAdmissions: [(
                event: OpalFusion.Mosaic.NostrNamespace.Event,
                source: RecoveredAdmission
            )]
            do {
                recoveredAdmissions = try Self.decodeRecoveredAdmissions(
                    admissionJournal.recoveredAdmissions
                )
            } catch {
                throw .invalidRecoveryAdmission
            }
            guard admissionJournal.requiresRuntimeRecovery
                    == !recoveredAdmissions.isEmpty else {
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
            self.admissionJournal = admissionJournal
            self.recoveredAdmissions = recoveredAdmissions
        }

        /// Authenticates every retained admission and rederives its exact journal record before
        /// any live route capability can be requested. The app-owned store is attempt-atomic;
        /// ingress construction reloads the same snapshot only after this pure mailbox check.
        static func validateRecoveredAdmissionsBeforeRouteProvisioning(
            bootstrap: Driver.Bootstrap,
            recipientCapabilities: [Transport.RecipientCapability],
            dependencies: Dependencies
        ) throws(InitializationError) {
            let recipientSet: RecipientSet
            do {
                recipientSet = try .init(recipientCapabilities)
            } catch {
                throw .invalidRecoveryAdmission
            }
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
            let recoveredAdmissions: [(
                event: OpalFusion.Mosaic.NostrNamespace.Event,
                source: RecoveredAdmission
            )]
            do {
                recoveredAdmissions = try decodeRecoveredAdmissions(
                    admissionJournal.recoveredAdmissions
                )
            } catch {
                throw .invalidRecoveryAdmission
            }
            let recoveredRecords = admissionJournal.recoveredRecords
            guard recoveredAdmissions.count == recoveredRecords.count,
                  admissionJournal.requiresRuntimeRecovery
                    == !recoveredAdmissions.isEmpty else {
                throw .runtimeRecoveryRequired
            }
            let transportContext = Transport.RuntimeContext(
                attemptIdentifier: bootstrap.attemptIdentifier,
                generationIdentifier: bootstrap.generationIdentifier,
                phaseStartUnixSeconds:
                    bootstrap.proposalValidation.core.deadlines.phaseStart
            )
            for ((giftWrap, source), expectedRecord) in zip(
                recoveredAdmissions,
                recoveredRecords
            ) {
                let recipientIdentity: Data
                do {
                    recipientIdentity = try Transport.recipientEventIdentity(
                        in: giftWrap
                    )
                } catch {
                    throw .invalidRecoveryAdmission
                }
                guard let recipient = recipientSet.capability(
                    for: recipientIdentity
                ) else {
                    throw .invalidRecoveryAdmission
                }
                let delivery: Transport.AuthenticatedDelivery
                do {
                    switch recipient.channel {
                    case .control:
                        delivery = try Transport.openControl(
                            giftWrap,
                            context: transportContext,
                            recipientSigningKey: recipient.signingKey,
                            currentUnixSeconds: source.acceptedAtUnixSeconds
                        )
                    case .anonymous:
                        delivery = try Transport.openAnonymous(
                            giftWrap,
                            context: transportContext,
                            recipientSigningKey: recipient.signingKey,
                            currentUnixSeconds: source.acceptedAtUnixSeconds
                        )
                    }
                } catch {
                    throw .invalidRecoveryAdmission
                }
                let derivedRecord: AdmissionJournal.AcceptedRecord
                switch delivery.storage {
                case let .control(delivery):
                    guard recipient.channel == .control else {
                        throw .invalidRecoveryAdmission
                    }
                    derivedRecord = .init(
                        control: delivery,
                        source: source
                    )
                case let .anonymous(delivery):
                    guard recipient.channel == .anonymous else {
                        throw .invalidRecoveryAdmission
                    }
                    derivedRecord = .init(
                        anonymous: delivery,
                        source: source
                    )
                }
                guard derivedRecord == expectedRecord else {
                    throw .invalidRecoveryAdmission
                }
            }
        }

        func start() async -> Bool {
            guard state == .idle else { return false }
            state = .starting
            await dependencies.beforeDriverStart()
            await driver.start()
            if !recoveredAdmissions.isEmpty {
                for (giftWrap, source) in recoveredAdmissions {
                    let recipientIdentity: Data
                    do {
                        recipientIdentity = try Transport.recipientEventIdentity(
                            in: giftWrap
                        )
                    } catch {
                        return await failRuntimeRecovery()
                    }
                    guard let recipient = recipientSet.capability(
                        for: recipientIdentity
                    ) else {
                        return await failRuntimeRecovery()
                    }
                    do {
                        guard try await driver.submit(
                            giftWrap,
                            to: recipient,
                            currentUnixSeconds: source.acceptedAtUnixSeconds,
                            source: source
                        ) else {
                            return await failRuntimeRecovery()
                        }
                    } catch {
                        return await failRuntimeRecovery()
                    }
                }
                guard await driver.awaitRuntimeRecoveryReplay(),
                      admissionJournal.completeRuntimeRecovery() else {
                    return await failRuntimeRecovery()
                }
            }
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

        private func failRuntimeRecovery() async -> Bool {
            state = .stopping
            _ = await driver.inputSourceDidTerminate(.failed)
            return false
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

            let acceptedAtUnixSeconds = dependencies.currentUnixSeconds()
            let source: RecoveredAdmission
            do {
                let limits = try Transport.codingLimits
                source = RecoveredAdmission(
                    canonicalGiftWrapBytes: try OpalFusion.Mosaic
                        .NostrNamespace.EventCodec.encode(
                            giftWrap,
                            limits: limits.event
                        ),
                    acceptedAtUnixSeconds: acceptedAtUnixSeconds
                )
            } catch {
                return .rejected(.runtimeRejected)
            }
            do {
                guard try await driver.submit(
                    giftWrap,
                    to: recipient,
                    currentUnixSeconds: acceptedAtUnixSeconds,
                    source: source
                ) else {
                    return .rejected(.runtimeRejected)
                }
            } catch let failure {
                return .rejected(.transport(failure))
            }
            return .accepted
        }

        private static func decodeRecoveredAdmissions(
            _ admissions: [RecoveredAdmission]
        ) throws -> [(
            event: OpalFusion.Mosaic.NostrNamespace.Event,
            source: RecoveredAdmission
        )] {
            let limits = try Transport.codingLimits
            return try admissions.map { admission in
                let event = try OpalFusion.Mosaic.NostrNamespace.EventCodec
                    .decode(
                        admission.canonicalGiftWrapBytes,
                        limits: limits.event
                    )
                guard try OpalFusion.Mosaic.NostrNamespace.EventCodec.encode(
                    event,
                    limits: limits.event
                ) == admission.canonicalGiftWrapBytes else {
                    throw InitializationError.invalidRecoveryAdmission
                }
                return (event, admission)
            }
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

        func terminalCompletionValidation() async -> CompleteTransactionValidation? {
            await driver.terminalCompletionValidation()
        }

        var currentPhase: OpalFusion.Mosaic.Attempt.Phase? {
            get async { await driver.currentPhase }
        }

        var terminalProtocolAbort: (
            phase: OpalFusion.Mosaic.Attempt.Phase,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        )? {
            get async { await driver.terminalProtocolAbort }
        }

        func submitAuthenticatedAbort(
            during phase: OpalFusion.Mosaic.Attempt.Phase,
            reason: OpalFusion.Mosaic.Attempt.AbortReason
        ) async -> Bool {
            guard state == .running else { return false }
            state = .stopping
            guard await driver.submitAuthenticatedAbort(
                during: phase,
                reason: reason
            ) else {
                await driver.stop()
                return false
            }
            return true
        }

        /// Freezes live admission, drains all prior coordinator inputs, then persists and applies
        /// one exact public terminal event at the resulting package-owned phase.
        func submitOrderedAuthenticatedAbort(
            deriving operation: @escaping @Sendable (
                OpalFusion.Mosaic.Attempt.Phase
            ) throws -> OpalFusion.Mosaic.Attempt.AbortReason
        ) async -> Bool {
            guard state == .running else { return false }
            state = .stopping
            guard await driver.awaitRuntimeRecoveryReplay(),
                  let phase = await driver.currentPhase else {
                await driver.stop()
                return false
            }
            let reason: OpalFusion.Mosaic.Attempt.AbortReason
            do {
                reason = try operation(phase)
            } catch {
                await driver.stop()
                return false
            }
            guard await driver.submitAuthenticatedAbort(
                during: phase,
                reason: reason
            ) else {
                await driver.stop()
                return false
            }
            return true
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
