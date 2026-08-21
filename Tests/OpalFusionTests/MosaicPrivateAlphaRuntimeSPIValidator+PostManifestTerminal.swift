// MosaicPrivateAlphaRuntimeSPIValidator+PostManifestTerminal.swift

import Foundation
import OpalCrypto
import Synchronization
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

extension MosaicPrivateAlphaRuntimeSPIValidator {
    @Test("Bound terminal record and evidence decoders fail closed")
    func boundTerminalRecordAndEvidenceDecoders() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeBinding(seed: 0xB6)
        #expect(
            throws: Runtime.Failure.opaqueByteCountLimitExceeded
        ) {
            _ = try Runtime.loadRecovery(
                from: Data(
                    count: Runtime.RecoveryState
                        .maximumSnapshotByteCount + 1
                ),
                expectedBinding: binding
            )
        }
        let conductor = fixture.formation.roleElection.roster.conductor
        let authority = try Alpha.PrivateDeploymentAbortAuthority
            .makePostManifestAuthority(
                phase: .walletReservation,
                participant: conductor,
                manifest: fixture.proof.proposalValidation.manifest,
                roundManifest: fixture.proof.completeManifest
            )
        let payload = try Alpha.PreManifestNostrPayloadDocument.makeAbort(
            .init(
                discoveryEpochStartUnixSeconds:
                    authority.discoveryEpochStartUnixSeconds,
                phase: authority.phase,
                context: authority.context,
                reason: .invalidAuthenticatedMessage
            ),
            authority: authority
        )
        let signing = try makeSigningCapability(
            fixture.formation.controlCandidate(for: conductor).signingKey,
            documentByte: 0xD0,
            eventByte: 0xD1
        )
        let event = try Runtime.PrivateDeploymentEvent.makeLocal(
            payload: payload,
            createdAtUnixSeconds:
                fixture.proof.completeManifest.core.deadlines.phaseStart,
            signing: signing
        )
        let record = try Runtime.PostManifestTerminalRecord.abort(
            binding: binding,
            phase: .walletReservation,
            event: event,
            wasReceived: true,
            manifest: fixture.proof.proposalValidation.manifest,
            roundManifest: fixture.proof.completeManifest
        ).record
        let recordBytes = try record.canonicalBytes()
        #expect(throws: (any Error).self) {
            _ = try Runtime.PostManifestTerminalRecord.decode(
                recordBytes + Data([0]),
                expectedBinding: binding
            )
        }
        #expect(throws: (any Error).self) {
            _ = try Runtime.PostManifestTerminalRecord.decode(
                Data(repeating: 0, count: 200_513),
                expectedBinding: binding
            )
        }
        let eventBytes = try event.canonicalRecoveryBytes()
        let phaseIndex = recordBytes.count - eventBytes.count - 5
        var unknownPhaseRecord = recordBytes
        unknownPhaseRecord[phaseIndex] = 0xFF
        #expect(throws: (any Error).self) {
            _ = try Runtime.PostManifestTerminalRecord.decode(
                unknownPhaseRecord,
                expectedBinding: binding
            )
        }

        let evidence = try Runtime.PostManifestTerminalEvidence(
            binding: binding,
            reason: .aborted,
            wasReceived: true,
            predecessorRevision: 1,
            predecessorSnapshotDigest: Data(repeating: 0x11, count: 32),
            localControlIdentity: Data(
                fixture.formation.roleElection.roster.contributors[0]
                    .validatedBytes
            ),
            terminalIdentity: Data(repeating: 0x22, count: 32),
            event: event,
            admissionSnapshotDigest: Data(repeating: 0x33, count: 32),
            publicationSnapshotDigest: Data(repeating: 0x44, count: 32)
        )
        let evidenceBytes = try evidence.canonicalBytes()
        #expect(throws: (any Error).self) {
            _ = try Runtime.PostManifestTerminalEvidence.decode(
                evidenceBytes + Data([0]),
                expectedBinding: binding
            )
        }
        #expect(throws: (any Error).self) {
            _ = try Runtime.PostManifestTerminalEvidence.decode(
                Data(
                    repeating: 0,
                    count: Runtime.RecoveryState.maximumOpaqueByteCount + 1
                ),
                expectedBinding: binding
            )
        }
    }

    @Test("Bind a conductor completion record to the exact transaction proof")
    func bindConductorCompletionRecordToExactTransaction() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeBinding(seed: 0xB9)
        let prepared = try await MosaicMainnetAlphaBCHCompletionFixtures
            .prepare(manifest: fixture.proof.completeManifest)
        let validation = try Alpha.PrivateDeploymentCompletionValidation(
            manifest: fixture.proof.proposalValidation.manifest,
            roundManifest: fixture.proof.completeManifest,
            completeTransactionValidation: prepared.validation
        )
        let payload = try Alpha.PreManifestNostrPayloadDocument
            .makeCompletion(
                .init(validation: validation),
                validation: validation
            )
        let conductor = fixture.formation.roleElection.roster.conductor
        let signing = try makeSigningCapability(
            fixture.formation.controlCandidate(for: conductor).signingKey,
            documentByte: 0xD4,
            eventByte: 0xD5
        )
        let event = try Runtime.PrivateDeploymentEvent.makeLocal(
            payload: payload,
            createdAtUnixSeconds:
                fixture.proof.completeManifest.core.deadlines.bchSigning,
            signing: signing
        )
        let record = try Runtime.PostManifestTerminalRecord.completion(
            binding: binding,
            event: event,
            validation: validation
        )
        let canonical = try record.canonicalBytes()
        let restored = try Runtime.PostManifestTerminalRecord.decode(
            canonical,
            expectedBinding: binding
        )
        #expect(restored == record)
        try restored.validateCompletion(validation)

        let differentPrepared = try await
            MosaicMainnetAlphaBCHCompletionFixtures.prepare(
                manifest: fixture.proof.completeManifest,
                componentSaltOffset: 1
            )
        let differentValidation = try Alpha
            .PrivateDeploymentCompletionValidation(
                manifest: fixture.proof.proposalValidation.manifest,
                roundManifest: fixture.proof.completeManifest,
                completeTransactionValidation:
                    differentPrepared.validation
            )
        #expect(throws: (any Error).self) {
            try restored.validateCompletion(differentValidation)
        }

        let contributor = try #require(
            fixture.formation.roleElection.roster.contributors.first
        )
        let contributorSigning = try makeSigningCapability(
            fixture.formation.controlCandidate(for: contributor).signingKey,
            documentByte: 0xD6,
            eventByte: 0xD7
        )
        #expect(
            throws: Alpha.PreManifestNostrCodec.ValidationError
                .signingIdentityMismatch
        ) {
            _ = try Runtime.PrivateDeploymentEvent.makeLocal(
                payload: payload,
                createdAtUnixSeconds:
                    fixture.proof.completeManifest.core.deadlines.bchSigning,
                signing: contributorSigning
            )
        }
        let lateEvent = try Runtime.PrivateDeploymentEvent(
            canonicalEventBytes: event.canonicalEventBytes,
            acceptedAtUnixSeconds:
                event.acceptedAtUnixSeconds + 1
        )
        #expect(throws: (any Error).self) {
            _ = try Runtime.PostManifestTerminalRecord.completion(
                binding: binding,
                event: lateEvent,
                validation: validation
            )
        }

        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routes = MosaicPrivateAlphaRuntimePersistenceStore()
        let capabilities = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: Data(conductor.validatedBytes),
                admissionStore: admission,
                publicationStore: publication,
                terminalStore: terminal,
                routeStore: routes
            )
        let sealedSnapshot = try makeSealedSnapshot(
            proof: fixture.proof,
            binding: binding,
            epoch: fixture.epoch
        )
        let owner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        _ = try await persist(
            owner.preparePostManifestRuntime(
                localControlIdentity: Data(conductor.validatedBytes),
                capabilities: capabilities
            ),
            on: owner
        )

        let transportFailure = Runtime.PostManifestTermination(
            binding: binding,
            kind: .transportFailed,
            reservationReference: nil,
            terminalIdentity: Data(repeating: 0xE0, count: 32),
            localControlIdentity: Data(conductor.validatedBytes),
            admissionSnapshotDigest: Data(repeating: 0xE1, count: 32),
            publicationSnapshotDigest: Data(repeating: 0xE2, count: 32),
            authority: .unavailable,
            outboundIsDrained: true,
            isLocalConductor: true,
            receivedTerminalEvent: nil,
            localTerminalEvent: nil
        )
        do {
            _ = try await owner.preparePostManifestTermination(
                consuming: transportFailure,
                createdAtUnixSeconds:
                    fixture.proof.completeManifest.core.deadlines.bchSigning,
                signing: nil
            )
            Issue.record("Transport failure manufactured terminal evidence")
        } catch Runtime.Failure.terminalEvidenceUnavailable {
            // Expected: transport loss remains recovery-required.
        }

        let admissionSnapshot = try #require(admission.load(binding))
        let publicationSnapshot = try #require(publication.load(binding))
        let admissionSnapshotDigest = Runtime.RecoveryState.sha256(
            admissionSnapshot
        )
        let publicationSnapshotDigest = Runtime.RecoveryState.sha256(
            publicationSnapshot
        )
        let localCompletionAuthority:
            Runtime.PostManifestTerminalAuthority = .completion(validation)
        let localCompletion = Runtime.PostManifestTermination(
            binding: binding,
            kind: .completed,
            reservationReference: nil,
            terminalIdentity: try Runtime.PostManifestExecution
                .makeTerminalIdentity(
                    binding: binding,
                    kind: .completed,
                    authority: localCompletionAuthority,
                    admissionSnapshotDigest: admissionSnapshotDigest,
                    publicationSnapshotDigest: publicationSnapshotDigest,
                    receivedTerminalEvent: nil
                ),
            localControlIdentity: Data(conductor.validatedBytes),
            admissionSnapshotDigest: admissionSnapshotDigest,
            publicationSnapshotDigest: publicationSnapshotDigest,
            authority: localCompletionAuthority,
            outboundIsDrained: true,
            isLocalConductor: true,
            receivedTerminalEvent: nil,
            localTerminalEvent: nil
        )
        let terminalSnapshot = try await persist(
            owner.preparePostManifestTermination(
                consuming: localCompletion,
                createdAtUnixSeconds:
                    fixture.proof.completeManifest.core.deadlines.bchSigning,
                signing: makeSigningCapability(
                    fixture.formation.controlCandidate(for: conductor)
                        .signingKey,
                    documentByte: 0xE6,
                    eventByte: 0xE7
                )
            ),
            on: owner
        )
        guard case .recover(.publishPrivateDeployment) = try await Runtime.Owner(
            claiming: Runtime.loadRecovery(
                from: terminalSnapshot,
                expectedBinding: binding
            )
        ).nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
    }

    @Test("Persist a received completion through execution and terminal owner")
    func persistReceivedCompletionThroughExecution() async throws {
        typealias FanIn = Alpha.PostManifestRelayFanIn
        typealias Ingress = Alpha.PostManifestTransportIngress
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let contributor = try #require(
            fixture.formation.roleElection.roster.contributors.first
        )
        let localIdentity = Data(contributor.validatedBytes)
        let binding = try makeBinding(seed: 0xBA)
        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routeProbe = MosaicPrivateAlphaRuntimePersistenceStore()
        let capabilities = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: localIdentity,
                admissionStore: admission,
                publicationStore: publication,
                terminalStore: terminal,
                routeStore: routeProbe
            )
        let sealedSnapshot = try makeSealedSnapshot(
            proof: fixture.proof,
            binding: binding,
            epoch: fixture.epoch
        )
        let owner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        _ = try await persist(
            owner.preparePostManifestRuntime(
                localControlIdentity: localIdentity,
                capabilities: capabilities
            ),
            on: owner
        )
        let construction = try await owner.makePostManifestConstruction(
            localControlIdentity: localIdentity
        )
        let relaySelection = try construction.makeRelaySelection(
            capabilities.relays
        )
        let publicationJournal = try construction.makePublicationJournal(
            relaySelection: relaySelection,
            persistence: capabilities.publicationPersistence
        )
        let codingLimits = try construction.makeCodingLimits(
            capabilities.relays
        )
        let prepared = try await MosaicMainnetAlphaBCHCompletionFixtures
            .prepare(manifest: fixture.proof.completeManifest)
        let completionValidation = try Alpha
            .PrivateDeploymentCompletionValidation(
                manifest: fixture.proof.proposalValidation.manifest,
                roundManifest: fixture.proof.completeManifest,
                completeTransactionValidation: prepared.validation
            )
        let completionPayload = try Alpha.PreManifestNostrPayloadDocument
            .makeCompletion(
                .init(validation: completionValidation),
                validation: completionValidation
            )
        let conductor = fixture.formation.roleElection.roster.conductor
        let conductorSigning = try makeSigningCapability(
            fixture.formation.controlCandidate(for: conductor).signingKey,
            documentByte: 0xE2,
            eventByte: 0xE3
        )
        let completionEvent = try Runtime.PrivateDeploymentEvent.makeLocal(
            payload: completionPayload,
            createdAtUnixSeconds:
                fixture.proof.completeManifest.core.deadlines.bchSigning,
            signing: conductorSigning
        )

        let recipient = Alpha.PostManifestNIP59Transport
            .RecipientCapability(
                channel: .control,
                signingKey: capabilities.mailboxes
                    .localControlRecipientSigningKey
            )
        let connections = relaySelection.endpoints.map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
        let subscriptions = try Dictionary(uniqueKeysWithValues:
            relaySelection.endpoints.enumerated().map { index, endpoint in
                (
                    endpoint,
                    try Nostr.SubscriptionIdentifier(
                        "terminal-completion-\(index)"
                    )
                )
            }
        )
        let recipientGroup = FanIn.RecipientRouteGroup(
            recipient: recipient,
            routes: zip(relaySelection.endpoints, connections).map {
                .init(endpoint: $0.0, connection: $0.1)
            },
            subscriptionIdentifiers: subscriptions
        )
        let completedState = Alpha.PostManifestRuntimeDriver.State
            .contributor(.terminal(.completed))
        let endpoint = FanIn.RuntimeEndpoint(
            start: { false },
            state: { Ingress.State.terminal(completedState) },
            submit: { _ in .rejected(.notRunning) },
            inputSourceDidTerminate: { _ in false },
            stop: {},
            waitForTermination: { completedState },
            terminalCompletionValidation: { prepared.validation }
        )
        let fanIn = try FanIn.makeComponent(
            role: .contributor,
            maximumAnonymousRecipientCount:
                fixture.proof.completeManifest.core.roster.contributors.count
                    * Alpha.componentCountPerContributor,
            manifestRelaySetDigest:
                fixture.proof.completeManifest.core.relaySetDigest,
            recipientRouteGroups: [recipientGroup],
            relaySelection: relaySelection,
            runtime: endpoint,
            codingLimits: codingLimits,
            maximumPendingEventCount: 8
        )
        let execution = Runtime.PostManifestExecution(
            binding: binding,
            fanIn: fanIn,
            publicationJournal: publicationJournal,
            privateManifest: fixture.proof.proposalValidation.manifest,
            completeManifest: fixture.proof.completeManifest,
            localControlIdentity: .init(
                validatedBytes: Array(localIdentity)
            ),
            recoveredTerminalEvidence: nil,
            loadAdmissionReadback: {
                guard let readback = admission.load(binding) else {
                    throw Runtime.Failure.terminalEvidenceUnavailable
                }
                return readback
            },
            loadPublicationReadback: {
                guard let readback = publication.load(binding) else {
                    throw Runtime.Failure.terminalEvidenceUnavailable
                }
                return readback
            },
            terminalPersistence: capabilities.terminalPersistence,
            stopOutbound: {},
            waitForOutboundDrain: { true }
        )
        try await execution.start()
        for connection in connections {
            #expect(await connection.openCount == 0)
        }
        try await execution.acceptReceivedCompletion(completionEvent)
        #expect(terminal.recordedCompareAndSwapCallCount == 1)
        guard let termination = try await execution.waitForTermination() else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(termination.kind == .completed)
        let authorizedSnapshot = try await persist(
            owner.preparePostManifestTermination(
                consuming: termination,
                createdAtUnixSeconds:
                    fixture.proof.completeManifest.core.deadlines.bchSigning,
                signing: nil
            ),
            on: owner
        )
        _ = try Runtime.loadRecovery(
            from: authorizedSnapshot,
            expectedBinding: binding
        )
        let evidence = try await owner.claimTerminalEvidence()
        #expect(evidence.binding == binding)
        #expect(routeProbe.recordedProvisionCallCount == 0)
        for connection in connections {
            #expect(await connection.openCount == 0)
        }

        let loaded = try Runtime.loadRecovery(
            from: authorizedSnapshot,
            expectedBinding: binding
        )
        let recoveredOwner = try Runtime.Owner(claiming: loaded)
        guard case let .recover(
            .validatePostManifestTerminal(recoveryContinuation)
        ) = try await recoveredOwner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        _ = try await recoveredOwner.resumePrivateDeployment(
            recoveryContinuation
        )
        let recoveredConstruction = try await recoveredOwner
            .makePostManifestConstruction(
                localControlIdentity: localIdentity
            )
        let recoveredRelaySelection = try recoveredConstruction
            .makeRelaySelection(capabilities.relays)
        let recoveredPublicationJournal = try recoveredConstruction
            .makePublicationJournal(
                relaySelection: recoveredRelaySelection,
                persistence: capabilities.publicationPersistence
            )
        let recoveredCodingLimits = try recoveredConstruction
            .makeCodingLimits(capabilities.relays)
        let recoveredConnections = recoveredRelaySelection.endpoints.map {
            _ in ScriptedMosaicTorWebSocketConnection()
        }
        let recoveredSubscriptions = try Dictionary(uniqueKeysWithValues:
            recoveredRelaySelection.endpoints.enumerated().map {
                index, endpoint in
                (
                    endpoint,
                    try Nostr.SubscriptionIdentifier(
                        "terminal-completion-recovery-\(index)"
                    )
                )
            }
        )
        let recoveredRecipientGroup = FanIn.RecipientRouteGroup(
            recipient: recipient,
            routes: zip(
                recoveredRelaySelection.endpoints,
                recoveredConnections
            ).map {
                .init(endpoint: $0.0, connection: $0.1)
            },
            subscriptionIdentifiers: recoveredSubscriptions
        )
        let recoveredEndpoint = FanIn.RuntimeEndpoint(
            start: { false },
            state: { Ingress.State.terminal(completedState) },
            submit: { _ in .rejected(.notRunning) },
            inputSourceDidTerminate: { _ in false },
            stop: {},
            waitForTermination: { completedState },
            terminalCompletionValidation: { prepared.validation }
        )
        let recoveredFanIn = try FanIn.makeComponent(
            role: .contributor,
            maximumAnonymousRecipientCount:
                fixture.proof.completeManifest.core.roster.contributors.count
                    * Alpha.componentCountPerContributor,
            manifestRelaySetDigest:
                fixture.proof.completeManifest.core.relaySetDigest,
            recipientRouteGroups: [recoveredRecipientGroup],
            relaySelection: recoveredRelaySelection,
            runtime: recoveredEndpoint,
            codingLimits: recoveredCodingLimits,
            maximumPendingEventCount: 8
        )
        let recoveredExecution = Runtime.PostManifestExecution(
            binding: binding,
            fanIn: recoveredFanIn,
            publicationJournal: recoveredPublicationJournal,
            privateManifest: fixture.proof.proposalValidation.manifest,
            completeManifest: fixture.proof.completeManifest,
            localControlIdentity: .init(
                validatedBytes: Array(localIdentity)
            ),
            recoveredTerminalEvidence:
                recoveredConstruction.recoveredTerminalEvidence,
            loadAdmissionReadback: {
                guard let readback = admission.load(binding) else {
                    throw Runtime.Failure.terminalEvidenceUnavailable
                }
                return readback
            },
            loadPublicationReadback: {
                guard let readback = publication.load(binding) else {
                    throw Runtime.Failure.terminalEvidenceUnavailable
                }
                return readback
            },
            terminalPersistence: capabilities.terminalPersistence,
            stopOutbound: {},
            waitForOutboundDrain: { true }
        )
        try await recoveredExecution.start()
        guard let recoveredTermination = try await recoveredExecution
            .waitForTermination() else {
            throw Runtime.Failure.invalidStateTransition
        }
        guard case .terminal(.cleanupAuthorized(.completed, _, _)) =
            try await recoveredOwner.validateRecoveredPostManifestTerminal(
                consuming: recoveredTermination
            ) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let recoveredEvidence = try await recoveredOwner
            .claimTerminalEvidence()
        #expect(recoveredEvidence.binding == binding)
        #expect(routeProbe.recordedProvisionCallCount == 0)
        for connection in recoveredConnections {
            #expect(await connection.openCount == 0)
        }
    }

    @Test("Linearize concurrent post-manifest termination claims")
    func linearizeConcurrentPostManifestTerminationClaims() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let contributorIdentity = try #require(
            fixture.formation.roleElection.roster.contributors.first
        )
        let localIdentity = Data(contributorIdentity.validatedBytes)
        let binding = try makeBinding(seed: 0xBC)
        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routeProbe = MosaicPrivateAlphaRuntimePersistenceStore()
        let baseCapabilities = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: localIdentity,
                admissionStore: admission,
                publicationStore: publication,
                terminalStore: terminal,
                routeStore: routeProbe
            )
        let relays = Runtime.PostManifestRelayCapabilities(
            provisionRoutes: { requests in
                routeProbe.recordProvisionCall()
                return requests.enumerated().map { requestIndex, request in
                    Runtime.PostManifestProvisionedRouteGroup(
                        recipientEventIdentity:
                            request.recipientEventIdentity,
                        routes: request.relayEndpointIdentifiers.enumerated()
                            .map { endpointIndex, endpoint in
                                Runtime.PostManifestProvisionedRoute(
                                    relayEndpointIdentifier: endpoint,
                                    connection:
                                        ScriptedMosaicPrivateAlphaTorConnection(),
                                    isolationIdentifier: UUID(
                                        uuid: (
                                            UInt8(requestIndex + 1),
                                            UInt8(endpointIndex + 1),
                                            0, 0, 0, 0, 0, 0,
                                            0, 0, 0, 0, 0, 0, 0, 0
                                        )
                                    )
                                )
                            }
                    )
                }
            },
            makeSubscriptionIdentifier:
                baseCapabilities.relays.makeSubscriptionIdentifier,
            awaitAnonymousPublicationPermit:
                baseCapabilities.relays.awaitAnonymousPublicationPermit,
            maximumSubscriptionIdentifierByteCount:
                baseCapabilities.relays
                    .maximumSubscriptionIdentifierByteCount,
            maximumPendingEventCount:
                baseCapabilities.relays.maximumPendingEventCount,
            maximumPendingRelayOutputCount:
                baseCapabilities.relays.maximumPendingRelayOutputCount
        )
        let capabilities = replacingRelays(
            baseCapabilities,
            with: relays
        )
        let sealedSnapshot = try makeSealedSnapshot(
            proof: fixture.proof,
            binding: binding,
            epoch: fixture.epoch
        )
        let owner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        _ = try await persist(
            owner.preparePostManifestRuntime(
                localControlIdentity: localIdentity,
                capabilities: capabilities
            ),
            on: owner
        )
        let construction = try await owner.makePostManifestConstruction(
            localControlIdentity: localIdentity
        )
        let controlIndex = try #require(
            fixture.formation.roleElection.roster.controlIdentities
                .firstIndex(of: contributorIdentity)
        )
        let execution = try await construction.makeContributorExecution(
            host: .init(
                transactionHost:
                    MosaicPrivateAlphaRejectingCompleteTransactionHost(),
                previousOutputSource:
                    MosaicPrivateAlphaRejectingPreviousOutputSource(),
                controlSigningKey: fixture.formation.controlCandidate(
                    for: contributorIdentity
                ).signingKey,
                controlEventSigningKey: try MosaicPrivateDeploymentFixtures
                    .CandidateKeyMaterial(
                        scalar: UInt8(125 + controlIndex)
                    ).signingKey,
                loadSlotSecrets: { _, _ in
                    throw Runtime.Failure.invalidStateTransition
                }
            ),
            capabilities: capabilities
        )
        #expect(routeProbe.recordedProvisionCallCount == 1)
        try await execution.start()

        let claimCounts = Mutex((claimed: 0, unavailable: 0))
        let first = Task { @Sendable in
            if let termination = try await execution.waitForTermination() {
                #expect(termination.binding == binding)
                claimCounts.withLock { $0.claimed += 1 }
            } else {
                claimCounts.withLock { $0.unavailable += 1 }
            }
        }
        let second = Task { @Sendable in
            if let termination = try await execution.waitForTermination() {
                #expect(termination.binding == binding)
                claimCounts.withLock { $0.claimed += 1 }
            } else {
                claimCounts.withLock { $0.unavailable += 1 }
            }
        }
        await Task.yield()
        await execution.stop()
        try await first.value
        try await second.value

        #expect(claimCounts.withLock { $0.claimed } == 1)
        #expect(claimCounts.withLock { $0.unavailable } == 1)
        #expect(routeProbe.recordedProvisionCallCount == 1)
    }

    @Test("Reject a misordered recovered abort without routes or a wait leak")
    func rejectMisorderedRecoveredAbortWithoutHanging() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let contributorIdentity = try #require(
            fixture.formation.roleElection.roster.contributors.first
        )
        let localIdentity = Data(contributorIdentity.validatedBytes)
        let binding = try makeBinding(seed: 0xC1)
        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routes = MosaicPrivateAlphaRuntimePersistenceStore()
        let capabilities = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: localIdentity,
                admissionStore: admission,
                publicationStore: publication,
                terminalStore: terminal,
                routeStore: routes
            )
        let sealedSnapshot = try makeSealedSnapshot(
            proof: fixture.proof,
            binding: binding,
            epoch: fixture.epoch
        )
        let owner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        _ = try await persist(
            owner.preparePostManifestRuntime(
                localControlIdentity: localIdentity,
                capabilities: capabilities
            ),
            on: owner
        )
        let conductor = fixture.formation.roleElection.roster.conductor
        let authority = try Alpha.PrivateDeploymentAbortAuthority
            .makePostManifestAuthority(
                phase: .groupedCommitment,
                participant: conductor,
                manifest: fixture.proof.proposalValidation.manifest,
                roundManifest: fixture.proof.completeManifest
            )
        let payload = try Alpha.PreManifestNostrPayloadDocument.makeAbort(
            .init(
                discoveryEpochStartUnixSeconds:
                    authority.discoveryEpochStartUnixSeconds,
                phase: authority.phase,
                context: authority.context,
                reason: .equivocation
            ),
            authority: authority
        )
        let signing = try makeSigningCapability(
            fixture.formation.controlCandidate(for: conductor).signingKey,
            documentByte: 0xD8,
            eventByte: 0xD9
        )
        let event = try Runtime.PrivateDeploymentEvent.makeLocal(
            payload: payload,
            createdAtUnixSeconds:
                fixture.proof.completeManifest.core.deadlines.phaseStart,
            signing: signing
        )
        let terminalRecord = try Runtime.PostManifestTerminalRecord.abort(
            binding: binding,
            phase: .groupedCommitment,
            event: event,
            wasReceived: true,
            manifest: fixture.proof.proposalValidation.manifest,
            roundManifest: fixture.proof.completeManifest
        ).record
        let terminalBytes = try terminalRecord.canonicalBytes()
        #expect(
            try terminal.compareAndSwap(binding, nil, terminalBytes)
                == terminalBytes
        )

        let construction = try await owner.makePostManifestConstruction(
            localControlIdentity: localIdentity
        )
        let controlIndex = try #require(
            fixture.formation.roleElection.roster.controlIdentities
                .firstIndex(of: contributorIdentity)
        )
        let execution = try await construction.makeContributorExecution(
            host: .init(
                transactionHost:
                    MosaicPrivateAlphaRejectingCompleteTransactionHost(),
                previousOutputSource:
                    MosaicPrivateAlphaRejectingPreviousOutputSource(),
                controlSigningKey: fixture.formation.controlCandidate(
                    for: contributorIdentity
                ).signingKey,
                controlEventSigningKey: try MosaicPrivateDeploymentFixtures
                    .CandidateKeyMaterial(
                        scalar: UInt8(125 + controlIndex)
                    ).signingKey,
                loadSlotSecrets: { _, _ in
                    throw Runtime.Failure.invalidStateTransition
                }
            ),
            capabilities: capabilities
        )
        #expect(routes.recordedProvisionCallCount == 0)

        await #expect(throws: (any Error).self) {
            try await execution.start()
        }
        #expect(routes.recordedProvisionCallCount == 0)
    }

    @Test("Recover a write-ahead local timeout after CAS before apply")
    func recoverLocalTimeoutAfterWriteAheadCAS() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let contributorIdentity = try #require(
            fixture.formation.roleElection.roster.contributors.first
        )
        let localIdentity = Data(contributorIdentity.validatedBytes)
        let binding = try makeBinding(seed: 0xC4)
        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routeProbe = MosaicPrivateAlphaRuntimePersistenceStore()
        let baseCapabilities = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: localIdentity,
                admissionStore: admission,
                publicationStore: publication,
                terminalStore: terminal,
                routeStore: routeProbe
            )
        let capabilities = replacingRelays(
            baseCapabilities,
            with: makeWorkingRelayCapabilities(
                from: baseCapabilities,
                routeProbe: routeProbe
            )
        )
        let sealedSnapshot = try makeSealedSnapshot(
            proof: fixture.proof,
            binding: binding,
            epoch: fixture.epoch
        )
        let firstOwner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        let initializedSnapshot = try await persist(
            firstOwner.preparePostManifestRuntime(
                localControlIdentity: localIdentity,
                capabilities: capabilities
            ),
            on: firstOwner
        )
        let firstConstruction = try await firstOwner
            .makePostManifestConstruction(
                localControlIdentity: localIdentity
            )
        let firstRuntime = MosaicPrivateAlphaTerminalRuntimeProbe(
            phase: .walletReservation
        )
        let firstComponent = try makeTerminalProbeExecution(
            construction: firstConstruction,
            capabilities: capabilities,
            admissionStore: admission,
            publicationStore: publication,
            endpoint: await firstRuntime.endpoint()
        )
        let firstExecution = firstComponent.execution
        try await firstExecution.start()
        for connection in firstComponent.connections {
            #expect(await connection.openCount == 1)
        }
        terminal.failNextCompareAndSwapAfterWriting()
        let signing = try makeSigningCapability(
            fixture.formation.controlCandidate(
                for: contributorIdentity
            ).signingKey,
            documentByte: 0xDA,
            eventByte: 0xDB
        )
        var didLoseTimeoutCASReadback = false
        do {
            try await firstExecution.requestTimeoutAbort(
                currentUnixSeconds: fixture.proof.completeManifest.core
                    .deadlines.walletReservation,
                signing: signing
            )
        } catch {
            didLoseTimeoutCASReadback = true
        }
        #expect(didLoseTimeoutCASReadback)
        let durableRecord = try #require(terminal.load(binding))
        guard case let .abort(
            recordBinding,
            phase,
            _,
            wasReceived
        ) = try Runtime.PostManifestTerminalRecord.decode(
            durableRecord,
            expectedBinding: binding
        ) else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(recordBinding == binding)
        #expect(phase == .walletReservation)
        #expect(!wasReceived)

        let recoveredOwner = try await resumedOwner(
            snapshot: initializedSnapshot,
            binding: binding
        )
        let recoveredConstruction = try await recoveredOwner
            .makePostManifestConstruction(
                localControlIdentity: localIdentity
            )
        let recoveredRuntime = MosaicPrivateAlphaTerminalRuntimeProbe(
            phase: .walletReservation
        )
        let recoveredComponent = try makeTerminalProbeExecution(
            construction: recoveredConstruction,
            capabilities: capabilities,
            admissionStore: admission,
            publicationStore: publication,
            endpoint: await recoveredRuntime.endpoint()
        )
        let recoveredExecution = recoveredComponent.execution
        #expect(routeProbe.recordedProvisionCallCount == 0)
        try await recoveredExecution.start()
        guard let termination = try await recoveredExecution
            .waitForTermination() else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(termination.kind == .aborted)
        #expect(termination.binding == binding)
        #expect(routeProbe.recordedProvisionCallCount == 0)
        for connection in recoveredComponent.connections {
            #expect(await connection.openCount == 0)
        }
        #expect(terminal.recordedCompareAndSwapCallCount == 1)

        let terminalSnapshot = try await persist(
            recoveredOwner.preparePostManifestTermination(
                consuming: termination,
                createdAtUnixSeconds:
                    fixture.proof.completeManifest.core.deadlines
                        .walletReservation,
                signing: nil
            ),
            on: recoveredOwner
        )
        guard case .recover(.publishPrivateDeployment) = try await Runtime.Owner(
            claiming: Runtime.loadRecovery(
                from: terminalSnapshot,
                expectedBinding: binding
            )
        ).nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
    }

    @Test("Revalidate a received abort and drained companions after reload")
    func revalidateReceivedAbortAfterReload() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let contributorIdentity = try #require(
            fixture.formation.roleElection.roster.contributors.first
        )
        let localIdentity = Data(contributorIdentity.validatedBytes)
        let binding = try makeBinding(seed: 0xC7)
        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routeProbe = MosaicPrivateAlphaRuntimePersistenceStore()
        let baseCapabilities = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: localIdentity,
                admissionStore: admission,
                publicationStore: publication,
                terminalStore: terminal,
                routeStore: routeProbe
            )
        let capabilities = replacingRelays(
            baseCapabilities,
            with: makeWorkingRelayCapabilities(
                from: baseCapabilities,
                routeProbe: routeProbe
            )
        )
        let sealedSnapshot = try makeSealedSnapshot(
            proof: fixture.proof,
            binding: binding,
            epoch: fixture.epoch
        )
        let owner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        _ = try await persist(
            owner.preparePostManifestRuntime(
                localControlIdentity: localIdentity,
                capabilities: capabilities
            ),
            on: owner
        )
        let construction = try await owner.makePostManifestConstruction(
            localControlIdentity: localIdentity
        )
        let liveRuntime = MosaicPrivateAlphaTerminalRuntimeProbe(
            phase: .walletReservation
        )
        let liveComponent = try makeTerminalProbeExecution(
            construction: construction,
            capabilities: capabilities,
            admissionStore: admission,
            publicationStore: publication,
            endpoint: await liveRuntime.endpoint()
        )
        let execution = liveComponent.execution
        try await execution.start()
        for connection in liveComponent.connections {
            #expect(await connection.openCount == 1)
        }

        let conductor = fixture.formation.roleElection.roster.conductor
        let authority = try Alpha.PrivateDeploymentAbortAuthority
            .makePostManifestAuthority(
                phase: .walletReservation,
                participant: conductor,
                manifest: fixture.proof.proposalValidation.manifest,
                roundManifest: fixture.proof.completeManifest
            )
        let payload = try Alpha.PreManifestNostrPayloadDocument.makeAbort(
            .init(
                discoveryEpochStartUnixSeconds:
                    authority.discoveryEpochStartUnixSeconds,
                phase: authority.phase,
                context: authority.context,
                reason: .equivocation
            ),
            authority: authority
        )
        let conductorSigning = try makeSigningCapability(
            fixture.formation.controlCandidate(for: conductor).signingKey,
            documentByte: 0xDC,
            eventByte: 0xDD
        )
        let receivedEvent = try Runtime.PrivateDeploymentEvent.makeLocal(
            payload: payload,
            createdAtUnixSeconds:
                fixture.proof.completeManifest.core.deadlines.phaseStart,
            signing: conductorSigning
        )
        try await execution.acceptReceivedAbort(receivedEvent)
        guard let termination = try await execution.waitForTermination() else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(termination.kind == .aborted)
        let authorizedSnapshot = try await persist(
            owner.preparePostManifestTermination(
                consuming: termination,
                createdAtUnixSeconds:
                    fixture.proof.completeManifest.core.deadlines.phaseStart,
                signing: nil
            ),
            on: owner
        )
        let freshEvidence = try await owner.claimTerminalEvidence()
        #expect(freshEvidence.binding == binding)
        #expect(routeProbe.recordedProvisionCallCount == 0)

        let authorizedState = try Runtime.RecoveryState.decode(
            from: authorizedSnapshot,
            expectedBinding: binding
        )
        guard case let .authorized(reason, evidenceBytes) =
            authorizedState.terminalState else {
            throw Runtime.Failure.invalidStateTransition
        }
        let evidence = try Runtime.PostManifestTerminalEvidence.decode(
            evidenceBytes,
            expectedBinding: binding
        )
        func altered(_ bytes: Data) -> Data {
            var replacement = bytes
            replacement[replacement.startIndex] ^= 0x01
            return replacement
        }
        let alteredEvent = try Runtime.PrivateDeploymentEvent(
            canonicalEventBytes: evidence.event.canonicalEventBytes,
            acceptedAtUnixSeconds:
                evidence.event.acceptedAtUnixSeconds + 1
        )
        let corruptEvidence: [Runtime.PostManifestTerminalEvidence] = [
            try .init(
                binding: binding,
                reason: .completed,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest,
                localControlIdentity: evidence.localControlIdentity,
                terminalIdentity: evidence.terminalIdentity,
                event: evidence.event,
                admissionSnapshotDigest: evidence.admissionSnapshotDigest,
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest
            ),
            try .init(
                binding: binding,
                reason: evidence.reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision + 1,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest,
                localControlIdentity: evidence.localControlIdentity,
                terminalIdentity: evidence.terminalIdentity,
                event: evidence.event,
                admissionSnapshotDigest: evidence.admissionSnapshotDigest,
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest
            ),
            try .init(
                binding: binding,
                reason: evidence.reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest: altered(
                    evidence.predecessorSnapshotDigest
                ),
                localControlIdentity: evidence.localControlIdentity,
                terminalIdentity: evidence.terminalIdentity,
                event: evidence.event,
                admissionSnapshotDigest: evidence.admissionSnapshotDigest,
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest
            ),
            try .init(
                binding: binding,
                reason: evidence.reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest,
                localControlIdentity: Data(repeating: 0xFF, count: 32),
                terminalIdentity: evidence.terminalIdentity,
                event: evidence.event,
                admissionSnapshotDigest: evidence.admissionSnapshotDigest,
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest
            ),
            try .init(
                binding: binding,
                reason: evidence.reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest,
                localControlIdentity: evidence.localControlIdentity,
                terminalIdentity: altered(evidence.terminalIdentity),
                event: evidence.event,
                admissionSnapshotDigest: evidence.admissionSnapshotDigest,
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest
            ),
            try .init(
                binding: binding,
                reason: evidence.reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest,
                localControlIdentity: evidence.localControlIdentity,
                terminalIdentity: evidence.terminalIdentity,
                event: alteredEvent,
                admissionSnapshotDigest: evidence.admissionSnapshotDigest,
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest
            ),
            try .init(
                binding: binding,
                reason: evidence.reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest,
                localControlIdentity: evidence.localControlIdentity,
                terminalIdentity: evidence.terminalIdentity,
                event: evidence.event,
                admissionSnapshotDigest: altered(
                    evidence.admissionSnapshotDigest
                ),
                publicationSnapshotDigest:
                    evidence.publicationSnapshotDigest
            ),
            try .init(
                binding: binding,
                reason: evidence.reason,
                wasReceived: evidence.wasReceived,
                predecessorRevision: evidence.predecessorRevision,
                predecessorSnapshotDigest:
                    evidence.predecessorSnapshotDigest,
                localControlIdentity: evidence.localControlIdentity,
                terminalIdentity: evidence.terminalIdentity,
                event: evidence.event,
                admissionSnapshotDigest: evidence.admissionSnapshotDigest,
                publicationSnapshotDigest: altered(
                    evidence.publicationSnapshotDigest
                )
            ),
        ]
        for corrupt in corruptEvidence {
            var corruptState = authorizedState
            corruptState.terminalState = .authorized(
                reason,
                exactEvidenceBytes: try corrupt.canonicalBytes()
            )
            let corruptSnapshot = try corruptState.canonicalBytes()
            #expect(throws: (any Error).self) {
                _ = try Runtime.loadRecovery(
                    from: corruptSnapshot,
                    expectedBinding: binding
                )
            }
        }

        let publicationReadback = try #require(publication.load(binding))
        publication.remove(binding)
        let missingCompanionLoaded = try Runtime.loadRecovery(
            from: authorizedSnapshot,
            expectedBinding: binding
        )
        let missingCompanionOwner = try Runtime.Owner(
            claiming: missingCompanionLoaded
        )
        guard case let .recover(
            .validatePostManifestTerminal(missingCompanionContinuation)
        ) = try await missingCompanionOwner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        _ = try await missingCompanionOwner.resumePrivateDeployment(
            missingCompanionContinuation
        )
        let missingCompanionConstruction = try await missingCompanionOwner
            .makePostManifestConstruction(
                localControlIdentity: localIdentity
            )
        var didRejectMissingCompanion = false
        do {
            _ = try await missingCompanionConstruction
                .makeContributorExecution(
                    host: try makeContributorHost(
                        formation: fixture.formation,
                        contributor: contributorIdentity
                    ),
                    capabilities: capabilities
                )
        } catch {
            didRejectMissingCompanion = true
        }
        #expect(didRejectMissingCompanion)
        #expect(routeProbe.recordedProvisionCallCount == 0)
        #expect(
            try publication.compareAndSwap(
                binding,
                nil,
                publicationReadback
            ) == publicationReadback
        )
        let admissionReadback = try #require(admission.load(binding))
        admission.remove(binding)
        let missingAdmissionLoaded = try Runtime.loadRecovery(
            from: authorizedSnapshot,
            expectedBinding: binding
        )
        let missingAdmissionOwner = try Runtime.Owner(
            claiming: missingAdmissionLoaded
        )
        guard case let .recover(
            .validatePostManifestTerminal(missingAdmissionContinuation)
        ) = try await missingAdmissionOwner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        _ = try await missingAdmissionOwner.resumePrivateDeployment(
            missingAdmissionContinuation
        )
        let missingAdmissionConstruction = try await missingAdmissionOwner
            .makePostManifestConstruction(
                localControlIdentity: localIdentity
            )
        var didRejectMissingAdmission = false
        do {
            _ = try await missingAdmissionConstruction
                .makeContributorExecution(
                    host: try makeContributorHost(
                        formation: fixture.formation,
                        contributor: contributorIdentity
                    ),
                    capabilities: capabilities
                )
        } catch {
            didRejectMissingAdmission = true
        }
        #expect(didRejectMissingAdmission)
        #expect(routeProbe.recordedProvisionCallCount == 0)
        #expect(
            try admission.compareAndSwap(
                binding,
                nil,
                admissionReadback
            ) == admissionReadback
        )

        let differentCompanionLoaded = try Runtime.loadRecovery(
            from: authorizedSnapshot,
            expectedBinding: binding
        )
        let differentCompanionOwner = try Runtime.Owner(
            claiming: differentCompanionLoaded
        )
        guard case let .recover(
            .validatePostManifestTerminal(differentCompanionContinuation)
        ) = try await differentCompanionOwner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        _ = try await differentCompanionOwner.resumePrivateDeployment(
            differentCompanionContinuation
        )
        let differentCompanionConstruction = try await
            differentCompanionOwner.makePostManifestConstruction(
                localControlIdentity: localIdentity
            )
        let relaySelection = try differentCompanionConstruction
            .makeRelaySelection(capabilities.relays)
        let journal = try differentCompanionConstruction
            .makePublicationJournal(
                relaySelection: relaySelection,
                persistence: capabilities.publicationPersistence
            )
        let companionAdmission = try MosaicPrivateDeploymentFixtures
            .makePostManifestControlRecoveryRecord(
                formation: fixture.formation,
                bootstrap: differentCompanionConstruction.bootstrap,
                recipientSigningKey: capabilities.mailboxes
                    .localControlRecipientSigningKey,
                acceptedAtUnixSeconds: fixture.proof.completeManifest.core
                    .deadlines.phaseStart + 1
            )
        guard case let .control(_, _, _, source) = companionAdmission else {
            throw Runtime.Failure.invalidStateTransition
        }
        let transportLimits = try Alpha.PostManifestNIP59Transport
            .codingLimits
        let giftWrapEvent = try OpalFusion.Mosaic.NostrNamespace.EventCodec
            .decode(
                source.canonicalGiftWrapBytes,
                limits: transportLimits.event
            )
        let giftWrap = try Alpha.PostManifestRelayPublisher.GiftWrap(
            validating: giftWrapEvent
        )
        let continuation = try journal.prepare(
            giftWrap,
            binding: .init(
                channelPurpose: .control,
                recipientEventIdentity: capabilities.mailboxes
                    .localControlRecipientSigningKey
                    .bip340VerificationKey.rawRepresentation,
                expiryUnixSeconds: fixture.proof.completeManifest.core
                    .deadlines.walletReservation
            )
        )
        for endpoint in continuation.publication.endpoints.prefix(2) {
            try journal.recordAttempt(
                eventIdentifier:
                    continuation.publication.eventIdentifier,
                endpoint: endpoint
            )
            try journal.recordAcknowledgement(
                .accepted,
                eventIdentifier:
                    continuation.publication.eventIdentifier,
                endpoint: endpoint
            )
        }
        try journal.recordCompletion(
            .transportAccepted,
            eventIdentifier: continuation.publication.eventIdentifier
        )
        #expect(journal.isDrained)
        let differentPublicationReadback = try #require(
            publication.load(binding)
        )
        #expect(differentPublicationReadback != publicationReadback)
        let differentCompanionRuntime = MosaicPrivateAlphaTerminalRuntimeProbe(
            phase: .walletReservation
        )
        let differentCompanionComponent = try makeTerminalProbeExecution(
            construction: differentCompanionConstruction,
            capabilities: capabilities,
            admissionStore: admission,
            publicationStore: publication,
            endpoint: await differentCompanionRuntime.endpoint()
        )
        let differentCompanionExecution =
            differentCompanionComponent.execution
        try await differentCompanionExecution.start()
        guard let differentCompanionTermination = try await
            differentCompanionExecution.waitForTermination() else {
            throw Runtime.Failure.invalidStateTransition
        }
        var didRejectDifferentCompanion = false
        do {
            _ = try await differentCompanionOwner
                .validateRecoveredPostManifestTerminal(
                    consuming: differentCompanionTermination
                )
        } catch {
            didRejectDifferentCompanion = true
        }
        #expect(didRejectDifferentCompanion)
        #expect(routeProbe.recordedProvisionCallCount == 0)
        for connection in differentCompanionComponent.connections {
            #expect(await connection.openCount == 0)
        }
        #expect(
            try publication.compareAndSwap(
                binding,
                differentPublicationReadback,
                publicationReadback
            ) == publicationReadback
        )

        let loaded = try Runtime.loadRecovery(
            from: authorizedSnapshot,
            expectedBinding: binding
        )
        let recoveredOwner = try Runtime.Owner(claiming: loaded)
        guard case let .recover(
            .validatePostManifestTerminal(continuation)
        ) = try await recoveredOwner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(continuation.binding == binding)
        #expect(
            try await recoveredOwner.resumePrivateDeployment(continuation)
                == .awaitingInput(.walletReservation)
        )
        let recoveredConstruction = try await recoveredOwner
            .makePostManifestConstruction(
                localControlIdentity: localIdentity
            )
        let recoveredRuntime = MosaicPrivateAlphaTerminalRuntimeProbe(
            phase: .walletReservation
        )
        let recoveredComponent = try makeTerminalProbeExecution(
            construction: recoveredConstruction,
            capabilities: capabilities,
            admissionStore: admission,
            publicationStore: publication,
            endpoint: await recoveredRuntime.endpoint()
        )
        let recoveredExecution = recoveredComponent.execution
        #expect(routeProbe.recordedProvisionCallCount == 0)
        try await recoveredExecution.start()
        guard let recoveredTermination = try await recoveredExecution
            .waitForTermination() else {
            throw Runtime.Failure.invalidStateTransition
        }
        guard case .terminal(.cleanupAuthorized(.aborted, _, _)) =
            try await recoveredOwner.validateRecoveredPostManifestTerminal(
                consuming: recoveredTermination
            ) else {
            throw Runtime.Failure.invalidStateTransition
        }
        let recoveredEvidence = try await recoveredOwner
            .claimTerminalEvidence()
        #expect(recoveredEvidence.binding == binding)
        #expect(routeProbe.recordedProvisionCallCount == 0)
        for connection in recoveredComponent.connections {
            #expect(await connection.openCount == 0)
        }
    }

    func makeTerminalProbeExecution(
        construction: borrowing Runtime.PostManifestConstruction,
        capabilities: Runtime.PostManifestRuntimeCapabilities,
        admissionStore: MosaicPrivateAlphaRuntimePersistenceStore,
        publicationStore: MosaicPrivateAlphaRuntimePersistenceStore,
        endpoint: Alpha.PostManifestRelayFanIn.RuntimeEndpoint
    ) throws -> (
        execution: Runtime.PostManifestExecution,
        connections: [ScriptedMosaicTorWebSocketConnection]
    ) {
        typealias FanIn = Alpha.PostManifestRelayFanIn
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace

        let relaySelection = try construction.makeRelaySelection(
            capabilities.relays
        )
        let publicationJournal = try construction.makePublicationJournal(
            relaySelection: relaySelection,
            persistence: capabilities.publicationPersistence
        )
        let codingLimits = try construction.makeCodingLimits(
            capabilities.relays
        )
        let recipient = Alpha.PostManifestNIP59Transport
            .RecipientCapability(
                channel: .control,
                signingKey: capabilities.mailboxes
                    .localControlRecipientSigningKey
            )
        let connections = relaySelection.endpoints.map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
        let subscriptions = try Dictionary(uniqueKeysWithValues:
            relaySelection.endpoints.enumerated().map { index, endpoint in
                (
                    endpoint,
                    try Nostr.SubscriptionIdentifier(
                        "terminal-probe-\(index)"
                    )
                )
            }
        )
        let recipientGroup = FanIn.RecipientRouteGroup(
            recipient: recipient,
            routes: zip(relaySelection.endpoints, connections).map {
                .init(endpoint: $0.0, connection: $0.1)
            },
            subscriptionIdentifiers: subscriptions
        )
        let fanIn = try FanIn.makeComponent(
            role: .contributor,
            maximumAnonymousRecipientCount:
                construction.completeManifest.core.roster.contributors.count
                    * Alpha.componentCountPerContributor,
            manifestRelaySetDigest:
                construction.completeManifest.core.relaySetDigest,
            recipientRouteGroups: [recipientGroup],
            relaySelection: relaySelection,
            runtime: endpoint,
            codingLimits: codingLimits,
            maximumPendingEventCount: 8
        )
        let binding = construction.binding
        return (
            Runtime.PostManifestExecution(
                binding: binding,
                fanIn: fanIn,
                publicationJournal: publicationJournal,
                privateManifest: construction.privateManifest,
                completeManifest: construction.completeManifest,
                localControlIdentity: .init(
                    validatedBytes: Array(construction.localControlIdentity)
                ),
                recoveredTerminalEvidence:
                    construction.recoveredTerminalEvidence,
                loadAdmissionReadback: {
                    guard let readback = admissionStore.load(binding) else {
                        throw Runtime.Failure.terminalEvidenceUnavailable
                    }
                    return readback
                },
                loadPublicationReadback: {
                    guard let readback = publicationStore.load(binding) else {
                        throw Runtime.Failure.terminalEvidenceUnavailable
                    }
                    return readback
                },
                terminalPersistence: capabilities.terminalPersistence,
                stopOutbound: {},
                waitForOutboundDrain: { true }
            ),
            connections
        )
    }
}
