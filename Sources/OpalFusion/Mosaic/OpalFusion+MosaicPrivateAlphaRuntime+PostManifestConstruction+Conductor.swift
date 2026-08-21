// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestConstruction+Conductor.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.PostManifestConstruction {
    /// Restores the exact RSA conductors and constructs the existing conductor coordinator,
    /// authenticated admission replay, outbound publication bridge, and Tor-only relay fan-in.
    @_spi(MosaicPrivateAlpha)
    public consuming func makeConductorExecution(
        host: consuming OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestConductorHost,
        capabilities: OpalFusion.MosaicPrivateAlphaRuntime
            .PostManifestRuntimeCapabilities
    ) async throws -> OpalFusion.MosaicPrivateAlphaRuntime
        .PostManifestExecution {
        guard isConductor else {
            throw Runtime.Failure.invalidStateTransition
        }
        let componentEvaluator = try OpalFusion.Mosaic.OpalV0
            .AuthorizationEvaluator.restore(
                securityKey: host.componentAuthorizationSecurityKey,
                expectedVerificationKey:
                    completeManifest.core
                        .componentAuthorizationVerificationKey
            )
        let signatureEvaluator = try OpalFusion.Mosaic.OpalV0
            .AuthorizationEvaluator.restore(
                securityKey: host.bchSignatureAuthorizationSecurityKey,
                expectedVerificationKey:
                    completeManifest.core
                        .bchSignatureAuthorizationVerificationKey
            )
        let previousOutputSource = host.previousOutputSource
        let controlSigningKey = host.controlSigningKey
        let controlEventSigningKey = host.controlEventSigningKey
        try capabilities.validateResourceLimits()
        let relaySelection = try makeRelaySelection(capabilities.relays)
        let transportOwner = try makeTransportOwner(
            capabilities: capabilities,
            relaySelection: relaySelection
        )
        let publicationJournal = try makePublicationJournal(
            relaySelection: relaySelection,
            persistence: capabilities.publicationPersistence
        )
        let codingLimits = try makeCodingLimits(capabilities.relays)
        let context = try ControlBridge.Context(
            validating: completeManifest,
            against: bootstrap
        )
        let recipients = capabilities.mailboxes.controlMailboxes.map {
            ControlBridge.Recipient(
                controlIdentity: .init(
                    validatedBytes: Array($0.controlIdentity)
                ),
                eventVerificationKey: $0.eventVerificationKey
            )
        }
        let publisher = try Alpha.PostManifestControlBatchPublisher(
            context: context,
            recipients: recipients,
            relaySelection: relaySelection,
            publicationJournal: publicationJournal,
            codingLimits: codingLimits,
            maximumPendingRelayOutputCount:
                capabilities.relays.maximumPendingRelayOutputCount,
            provideRoutes: transportOwner.controlRouteProvider
        )
        let deadlines = completeManifest.core.deadlines
        let timing = capabilities.timing
        let bridge = try ControlBridge(
            context: context,
            controlSigningKey: controlSigningKey,
            eventSigningKey: controlEventSigningKey,
            recipients: recipients,
            dependencies: .init(
                makeLayerTimestamps: { request in
                    try Self.makeLayerTimestamps(
                        timing.makeLayerTimestamps(Self.makeTimestampRequest(
                            recipientEventIdentity: nil,
                            phase: request.phase,
                            sequence: request.sequence,
                            expiryUnixSeconds: request.expiryUnixSeconds,
                            deadlines: deadlines
                        ))
                    )
                },
                handoffGiftWrapBatch: { batch in
                    try await publisher.publish(batch)
                }
            )
        )
        let roleDependencies = Alpha.PostManifestRuntimeDriver
            .RoleDependencies.conductor(.init(
                componentAuthorizationEvaluator: componentEvaluator,
                bchSignatureAuthorizationEvaluator: signatureEvaluator,
                previousOutputSource: previousOutputSource,
                maximumPendingInputCount:
                    capabilities.maximumPendingInputCount,
                handoffPublication: { validation in
                    let expiry: UInt64
                    switch validation.publication {
                    case .authorizationResponseSet:
                        expiry = deadlines.walletReservation
                    case .commitmentSet:
                        expiry = deadlines.groupedCommitment
                    case .componentSet:
                        expiry = deadlines.anonymousComponentSubmission
                    case .preSignAcknowledgementSet:
                        expiry = deadlines.transcriptAgreement
                    case .bchSignatureSet, .completeTransaction:
                        expiry = deadlines.bchSigning
                    }
                    try await bridge.publish(
                        validation,
                        expiryUnixSeconds: expiry
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
        let executionBinding = binding
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
            stopOutbound: {},
            waitForOutboundDrain: { publicationJournal.isDrained }
        )
    }
}
#endif
