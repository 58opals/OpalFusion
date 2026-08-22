// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestConstruction+Contributor.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.PostManifestConstruction {
    /// Constructs the existing contributor coordinator, exact outbound bridges, admission replay,
    /// and Tor-only relay fan-in from one validated private-deployment proof.
    @_spi(MosaicPrivateAlpha)
    public consuming func makeContributorExecution(
        host: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestContributorHost,
        capabilities: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestRuntimeCapabilities
    ) async throws -> OpalFusion.MosaicPrivateAlphaRuntime
        .PostManifestExecution {
        typealias ContributorBridge = Alpha
            .PostManifestContributorTransportBridge
        guard !isConductor else {
            throw Runtime.Failure.invalidStateTransition
        }
        try capabilities.validateResourceLimits()
        let executionBinding = binding
        let relaySelection = try makeRelaySelection(capabilities.relays)
        let transportOwner = try makeTransportOwner(
            capabilities: capabilities,
            relaySelection: relaySelection
        )
        let publicationJournal = try makePublicationJournal(
            relaySelection: relaySelection,
            persistence: capabilities.publicationPersistence
        )
        let terminalRecordBytes = try capabilities.terminalPersistence
            .load(binding)
        if let terminalRecordBytes {
            _ = try Runtime.PostManifestTerminalRecord.decode(
                terminalRecordBytes,
                expectedBinding: binding
            )
        }
        let terminalRecoveryRequired = recoveredTerminalEvidence != nil
            || terminalRecordBytes != nil
        let codingLimits = try makeCodingLimits(capabilities.relays)
        let deadlines = completeManifest.core.deadlines
        let timing = capabilities.timing
        let controlContext = try ContributorBridge.ControlBridge.Context(
            validating: completeManifest,
            against: bootstrap
        )
        let makeLocalContributionMaterial: @Sendable (
            Alpha.ReservationCoordinator.ReservationEligibility,
            OpalFusion.Host.MosaicReservationLease
        ) async throws -> Alpha.LocalContributionMaterial = {
            eligibility,
            lease in
            let secrets = try await host.loadSlotSecrets(
                executionBinding,
                lease
            ).map { try $0.makeInternal() }
            let candidate = try Alpha.LocalContributionMaterial.build(
                attemptIdentifier: eligibility.context.attemptIdentifier,
                generationIdentifier:
                    eligibility.context.generationIdentifier,
                materialIdentifier:
                    eligibility.context.materialIdentifier,
                contributor: eligibility.context.localControlIdentity,
                manifest: eligibility.manifest,
                reservationLease: lease,
                slotSecrets: secrets
            )
            let candidateRecoveryStates = candidate
                .componentSlotAuthorizationRecoveryStates.map {
                    Runtime
                        .PostManifestComponentSlotAuthorizationRecoveryState(
                            $0
                        )
                }
            let installedRecoveryStates = try await host
                .installOrLoadAuthorizationRecoveryStates(
                    executionBinding,
                    lease,
                    candidateRecoveryStates
                )
            let material: Alpha.LocalContributionMaterial
            if installedRecoveryStates == candidateRecoveryStates {
                material = candidate
            } else {
                material = try Alpha.LocalContributionMaterial.build(
                    attemptIdentifier:
                        eligibility.context.attemptIdentifier,
                    generationIdentifier:
                        eligibility.context.generationIdentifier,
                    materialIdentifier:
                        eligibility.context.materialIdentifier,
                    contributor: eligibility.context.localControlIdentity,
                    manifest: eligibility.manifest,
                    reservationLease: lease,
                    slotSecrets: secrets,
                    authorizationRecoveryStates:
                        try installedRecoveryStates.map {
                            try $0.makeInternal()
                        }
                )
            }
            try Alpha.ReservationMaterialLeaseValidator.validate(
                actualLease: lease,
                materialLease: material.reservationLease
            )
            guard try ContributorBridge.ControlBridge.Context(
                validating: material,
                against: eligibility.context
            ) == controlContext else {
                throw Runtime.Failure.invalidStateTransition
            }
            return material
        }
        let executionDependencies: Alpha.ReservationCoordinator
            .ExecutionDependencies
        let stopOutbound: @Sendable () async -> Void
        let waitForOutboundDrain: @Sendable () async -> Bool
        if terminalRecoveryRequired {
            typealias Journal = Alpha.PostManifestRelayPublicationJournal
            let recovery = try Journal.TerminalRecovery(
                journal: publicationJournal
            )
            let controlRecipientEventIdentities = transportOwner
                .controlRecipients.map {
                    $0.eventVerificationKey.rawRepresentation
                }
            executionDependencies = .init(
                transactionHost: host.transactionHost,
                previousOutputSource: host.previousOutputSource,
                makeLocalContributionMaterial:
                    makeLocalContributionMaterial,
                publishPlayerCommit: { validation in
                    let request = validation.request
                    guard controlContext.roster.contributors.contains(
                            controlContext.localControlIdentity
                          ), request.attemptIdentifier
                            == controlContext.attemptIdentifier,
                          request.generationIdentifier
                            == controlContext.generationIdentifier,
                          request.materialIdentifier
                            == controlContext.materialIdentifier,
                          request.contributor
                            == controlContext.localControlIdentity,
                          request.manifest == controlContext.manifest else {
                        throw Runtime.Failure.invalidStateTransition
                    }
                    let reservation = try ContributorBridge.ControlBridge
                        .makeAggregateReservation(
                            for: .playerCommit(request.playerCommit)
                        )
                    try await recovery.replay(
                        batchCount: reservation.fragmentCount + 1,
                        on: .control,
                        to: controlRecipientEventIdentities,
                        expiringAt: deadlines.groupedCommitment
                    )
                },
                publishAnonymousComponents: { validation in
                    guard validation.context == controlContext else {
                        throw Runtime.Failure.invalidStateTransition
                    }
                    try await recovery.replay(
                        batchCount: 1,
                        on: .anonymousComponents,
                        to: validation.entries.map {
                            Data($0.recipientEventIdentity)
                        },
                        expiringAt:
                            deadlines.anonymousComponentSubmission
                    )
                },
                publishPreSignAcknowledgement: { validation in
                    let transcript = validation.transcript
                    guard controlContext.roster.contributors.contains(
                            controlContext.localControlIdentity
                          ), validation.attemptIdentifier
                            == controlContext.attemptIdentifier,
                          validation.generationIdentifier
                            == controlContext.generationIdentifier,
                          validation.materialIdentifier
                            == controlContext.materialIdentifier,
                          validation.contributor
                            == controlContext.localControlIdentity,
                          transcript.manifest.roundIdentifier
                            == controlContext.roundIdentifier,
                          transcript.manifest
                            == controlContext.manifest.binding else {
                        throw Runtime.Failure.invalidStateTransition
                    }
                    try await recovery.replay(
                        batchCount: 1,
                        on: .control,
                        to: controlRecipientEventIdentities,
                        expiringAt: deadlines.transcriptAgreement
                    )
                },
                publishLocalBCHSignatures: { validation in
                    guard validation.context == controlContext else {
                        throw Runtime.Failure.invalidStateTransition
                    }
                    try await recovery.replay(
                        batchCount: 1,
                        on: .anonymousBCHSignatures,
                        to: validation.entries.map {
                            Data($0.recipientEventIdentity)
                        },
                        expiringAt: deadlines.bchSigning
                    )
                }
            )
            stopOutbound = {}
            waitForOutboundDrain = { await recovery.isComplete }
        } else {
            let bridge = try ContributorBridge(
                bootstrap: bootstrap,
                manifest: completeManifest,
                controlSigningKey: host.controlSigningKey,
                controlEventSigningKey: host.controlEventSigningKey,
                relaySelection: relaySelection,
                codingLimits: codingLimits,
                maximumPendingRelayOutputCount:
                    capabilities.relays.maximumPendingRelayOutputCount,
                dependencies: .init(
                    makeExpiryUnixSeconds: { publication in
                        switch publication {
                        case .playerCommit: deadlines.groupedCommitment
                        case .anonymousComponents:
                            deadlines.anonymousComponentSubmission
                        case .preSignAcknowledgement:
                            deadlines.transcriptAgreement
                        case .localBCHSignatures: deadlines.bchSigning
                        }
                    },
                    makeControlLayerTimestamps: { request in
                        try Self.makeLayerTimestamps(
                            timing.makeLayerTimestamps(
                                Self.makeTimestampRequest(
                                    recipientEventIdentity: nil,
                                    phase: request.phase,
                                    sequence: request.sequence,
                                    expiryUnixSeconds:
                                        request.expiryUnixSeconds,
                                    deadlines: deadlines
                                )
                            )
                        )
                    },
                    makeAnonymousLayerTimestamps: { request in
                        try Self.makeLayerTimestamps(
                            timing.makeLayerTimestamps(
                                Self.makeTimestampRequest(
                                    recipientEventIdentity:
                                        request.recipientEventIdentity,
                                    phase: request.phase,
                                    sequence: request.sequence,
                                    expiryUnixSeconds:
                                        request.expiryUnixSeconds,
                                    deadlines: deadlines
                                )
                            )
                        )
                    },
                    attemptTransportOwner: transportOwner,
                    publicationJournal: publicationJournal,
                    awaitAnonymousPublicationPermit: { request in
                        let kind: Runtime.PostManifestPublicationKind
                        switch request.kind {
                        case .components: kind = .anonymousComponents
                        case .bchSignatures: kind = .localBCHSignatures
                        }
                        try await capabilities.relays
                            .awaitAnonymousPublicationPermit(.init(
                                kind: kind,
                                recipientEventIdentity:
                                    request.recipientEventIdentity
                            ))
                    }
                )
            )
            executionDependencies = bridge.makeExecutionDependencies(
                transactionHost: host.transactionHost,
                previousOutputSource: host.previousOutputSource,
                makeLocalContributionMaterial:
                    makeLocalContributionMaterial
            )
            stopOutbound = { await bridge.requestStop() }
            waitForOutboundDrain = {
                let state = await bridge.waitForTermination()
                switch state {
                case .completed, .terminal: return true
                default: return false
                }
            }
        }
        let expectedReservationExpiration = Date(
            timeIntervalSince1970: TimeInterval(deadlines.walletReservation)
        )
        let roleDependencies = Alpha.PostManifestRuntimeDriver
            .RoleDependencies.contributor(.init(
                execution: executionDependencies,
                expectedReservationExpiration:
                    expectedReservationExpiration,
                maximumPendingInputCount:
                    capabilities.maximumPendingInputCount,
                makeReservationRequest: { eligibility in
                    let manifest = eligibility.manifest
                    let requiredExcess = try Alpha.ContributionFeePolicy
                        .requiredExcessFeeSatoshis(
                            for: eligibility.context.localControlIdentity,
                            in: eligibility.context.roster
                        )
                    return try OpalFusion.Host.MosaicReservationRequest(
                        attemptIdentifier: eligibility.context
                            .attemptIdentifier.validatedBytes,
                        networkGenesisHash:
                            manifest.core.networkGenesisHash,
                        roundIdentifier: manifest.core.roundIdentifier,
                        expiresAt: expectedReservationExpiration,
                        componentCount: Int(manifest.core.componentCount),
                        feeRateSatoshisPerByte:
                            manifest.core.feeRateSatoshisPerByte,
                        minimumExcessFeeSatoshis:
                            manifest.core.minimumExcessFeeSatoshis,
                        maximumExcessFeeSatoshis:
                            manifest.core.maximumExcessFeeSatoshis,
                        requiredExcessFeeSatoshis: requiredExcess,
                        transactionProfileIdentifier:
                            manifest.core.transactionProfileIdentifier
                    )
                }
            ))
        let admissionContext = makeAdmissionContext(capabilities)
        try Alpha.PostManifestAdmissionJournal.initializeRecoverySnapshot(
            binding: binding,
            persistence: capabilities.admissionPersistence,
            context: admissionContext,
            requireExisting: true
        )
        let admissionDependencies = Alpha.PostManifestTransportIngress
            .Dependencies(
                currentUnixSeconds: timing.currentUnixSeconds,
                admissionJournalStore: Alpha.PostManifestAdmissionJournal
                    .recoveryStore(
                        binding: binding,
                        persistence: capabilities.admissionPersistence
                    )
            )
        try Alpha.PostManifestTransportIngress
            .validateRecoveredAdmissionsBeforeRouteProvisioning(
                bootstrap: bootstrap,
                recipientCapabilities:
                    transportOwner.inboundRecipientCapabilities,
                dependencies: admissionDependencies
            )
        let fanIn: FanIn
        if terminalRecoveryRequired {
            let inbound = try await transportOwner
                .prepareTerminalRecoveryInboundRuntime()
            fanIn = try FanIn.makeTerminalRecovery(
                bootstrap: bootstrap,
                roleDependencies: roleDependencies,
                inboundRuntimeProvisioning: inbound,
                ingressDependencies: admissionDependencies,
                maximumPendingEventCount:
                    capabilities.relays.maximumPendingEventCount
            )
        } else {
            let inbound = try await transportOwner.provisionInboundRuntime()
            fanIn = try await FanIn.make(
                bootstrap: bootstrap,
                roleDependencies: roleDependencies,
                inboundRuntimeProvisioning: inbound,
                ingressDependencies: admissionDependencies,
                codingLimits: codingLimits,
                maximumPendingEventCount:
                    capabilities.relays.maximumPendingEventCount
            )
        }
        let publicationPersistence = capabilities.publicationPersistence
        let admissionPersistence = capabilities.admissionPersistence
        let publicationContext = publicationJournal.recoveryContext
        return .init(
            binding: binding,
            fanIn: fanIn,
            publicationJournal: publicationJournal,
            privateManifest: privateManifest,
            completeManifest: completeManifest,
            localControlIdentity: bootstrap.localControlIdentity,
            recoveredTerminalEvidence: recoveredTerminalEvidence,
            loadAdmissionReadback: {
                guard let bytes = try admissionPersistence.load(
                    executionBinding
                ) else {
                    throw Runtime.Failure.terminalEvidenceUnavailable
                }
                try Alpha.PostManifestAdmissionJournal
                    .validateRecoveryReadback(
                        bytes,
                        expectedContext: admissionContext
                    )
                return bytes
            },
            loadPublicationReadback: {
                guard let bytes = try publicationPersistence.load(
                    executionBinding
                ), try Alpha.PostManifestRelayPublicationJournal
                    .validateDrainedRecoveryReadback(
                        bytes,
                        expectedContext: publicationContext
                    ) else {
                    throw Runtime.Failure.terminalEvidenceUnavailable
                }
                return bytes
            },
            terminalPersistence: capabilities.terminalPersistence,
            stopOutbound: stopOutbound,
            waitForOutboundDrain: waitForOutboundDrain
        )
    }
}
#endif
