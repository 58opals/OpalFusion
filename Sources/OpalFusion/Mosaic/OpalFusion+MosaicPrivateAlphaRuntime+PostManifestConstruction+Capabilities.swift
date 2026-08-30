// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestConstruction+Capabilities.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.PostManifestConstruction {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias AttemptTransportOwner = Alpha.PostManifestAttemptTransportOwner
    typealias ControlBridge = Alpha.PostManifestControlPublicationBridge
    typealias FanIn = Alpha.PostManifestRelayFanIn
    typealias Journal = Alpha.PostManifestRelayPublicationJournal
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
    typealias Transport = Alpha.PostManifestNIP59Transport

    func initializeJournalSnapshots(
        _ capabilities: Runtime.PostManifestRuntimeCapabilities
    ) throws {
        try capabilities.validateResourceLimits()
        try validateMailboxCardinality(capabilities.mailboxes)
        let relaySelection = try makeRelaySelection(capabilities.relays)
        _ = try makeTransportOwner(
            capabilities: capabilities,
            relaySelection: relaySelection
        )
        let publicationContext = try makePublicationRecoveryContext(
            relaySelection: relaySelection
        )
        try Journal.initializeRecoverySnapshot(
            binding: binding,
            persistence: capabilities.publicationPersistence,
            context: publicationContext,
            requireExisting: false,
            requireEmpty: true
        )
        try Alpha.PostManifestAdmissionJournal.initializeRecoverySnapshot(
            binding: binding,
            persistence: capabilities.admissionPersistence,
            context: makeAdmissionContext(capabilities),
            requireExisting: false,
            requireEmpty: true
        )
    }

    func makeRelaySelection(
        _ capabilities: Runtime.PostManifestRelayCapabilities
    ) throws -> Alpha.PostManifestRelaySelectionValidation {
        let identifiers = relaySet.registrations.map {
            $0.endpoint.normalizedURL
        }
        let endpoints = identifiers.map {
            OpalFusion.Mosaic.RelayPublicationTracker.Endpoint(
                validatedIdentifier: $0
            )
        }
        return try .init(
            manifestRelaySetDigest: completeManifest.core.relaySetDigest,
            endpoints: endpoints,
            using: Runtime.RelaySelectionValidator(
                manifestRelaySetDigest:
                    completeManifest.core.relaySetDigest,
                endpointIdentifiers: identifiers
            )
        )
    }

    func makeTransportOwner(
        capabilities: Runtime.PostManifestRuntimeCapabilities,
        relaySelection: Alpha.PostManifestRelaySelectionValidation
    ) throws -> AttemptTransportOwner {
        try validateMailboxCardinality(capabilities.mailboxes)
        let context = try ControlBridge.Context(
            validating: completeManifest,
            against: bootstrap
        )
        let role: OpalFusion.Mosaic.Role = isConductor
            ? .conductor : .contributor
        let controlRecipients = capabilities.mailboxes.controlMailboxes.map {
            ControlBridge.Recipient(
                controlIdentity: .init(
                    validatedBytes: Array($0.controlIdentity)
                ),
                eventVerificationKey: $0.eventVerificationKey
            )
        }
        let localControlCapability = Transport.RecipientCapability(
            channel: .control,
            signingKey: capabilities.mailboxes
                .localControlRecipientSigningKey
        )
        let anonymous: AttemptTransportOwner.AnonymousMailboxProjection
        switch capabilities.mailboxes.anonymous {
        case let .contributor(keys):
            anonymous = .contributor(keys)
        case let .conductor(keys):
            anonymous = .conductor(keys.map {
                Transport.RecipientCapability(
                    channel: .anonymous,
                    signingKey: $0
                )
            })
        }
        let projection = AttemptTransportOwner
            .AuthenticatedMailboxProjection(
                binding: .init(context: context, role: role),
                controlRecipients: controlRecipients,
                localControlRecipientCapability: localControlCapability,
                anonymous: anonymous
            )
        let runtimeBinding = binding
        let relayCapabilities = capabilities.relays
        return try AttemptTransportOwner(
            bootstrap: bootstrap,
            manifest: completeManifest,
            mailboxProjection: projection,
            relaySelection: relaySelection,
            dependencies: .init(
                provisionRoutes: { requests in
                    let publicRequests = requests.map {
                        Runtime.PostManifestRouteRequest(
                            binding: runtimeBinding,
                            purpose: Self.publicPurpose($0.purpose),
                            recipientEventIdentity:
                                $0.recipientEventIdentity,
                            relayEndpointIdentifiers:
                                $0.endpoints.map(\.validatedIdentifier)
                        )
                    }
                    let groups = try await relayCapabilities
                        .provisionRoutes(publicRequests)
                    let provisionedConnections = groups.flatMap(\.routes)
                        .map { ObjectIdentifier($0.connection as AnyObject) }
                    guard Set(provisionedConnections).count
                            == provisionedConnections.count else {
                        throw Runtime.Failure.invalidStateTransition
                    }
                    return try groups.map { group in
                        .init(
                            recipientEventIdentity:
                                group.recipientEventIdentity,
                            routes: try group.routes.map { route in
                                .init(
                                    endpoint: .init(
                                        validatedIdentifier:
                                            route.relayEndpointIdentifier
                                    ),
                                    connection: try Runtime
                                        .TorWebSocketConnectionAdapter(
                                            route.connection,
                                            maximumPendingMessageCount:
                                                relayCapabilities
                                                    .maximumPendingEventCount
                                        ),
                                    isolationLease: .init(
                                        opaqueIdentifier:
                                            route.isolationIdentifier
                                    )
                                )
                            }
                        )
                    }
                },
                makeSubscriptionIdentifier: { request, endpoint in
                    let publicRequest = Runtime.PostManifestRouteRequest(
                        binding: runtimeBinding,
                        purpose: Self.publicPurpose(request.purpose),
                        recipientEventIdentity:
                            request.recipientEventIdentity,
                        relayEndpointIdentifiers:
                            request.endpoints.map(\.validatedIdentifier)
                    )
                    let value = try relayCapabilities
                        .makeSubscriptionIdentifier(
                            publicRequest,
                            endpoint.validatedIdentifier
                        )
                    guard value.utf8.count <= relayCapabilities
                            .maximumSubscriptionIdentifierByteCount else {
                        throw Runtime.Failure.invalidStateTransition
                    }
                    return try Nostr.SubscriptionIdentifier(
                        value
                    )
                }
            )
        )
    }

    private func validateMailboxCardinality(
        _ mailboxes: Runtime.PostManifestMailboxCapabilities
    ) throws {
        let roster = completeManifest.core.roster
        guard mailboxes.controlMailboxes.count
                == roster.controlIdentities.count else {
            throw Runtime.Failure.invalidStateTransition
        }
        switch (isConductor, mailboxes.anonymous) {
        case let (true, .conductor(keys)):
            guard keys.count == roster.contributors.count
                    * Alpha.componentCountPerContributor else {
                throw Runtime.Failure.invalidStateTransition
            }
        case let (false, .contributor(keys)):
            guard keys.count == Alpha.componentCountPerContributor else {
                throw Runtime.Failure.invalidStateTransition
            }
        case (true, .contributor), (false, .conductor):
            throw Runtime.Failure.invalidStateTransition
        }
    }

    func makePublicationJournal(
        relaySelection: Alpha.PostManifestRelaySelectionValidation,
        persistence: Runtime.PostManifestPublicationPersistence
    ) throws -> Journal {
        let recoveryContext = try makePublicationRecoveryContext(
            relaySelection: relaySelection
        )
        try Journal.initializeRecoverySnapshot(
            binding: binding,
            persistence: persistence,
            context: recoveryContext,
            requireExisting: true
        )
        return try .init(
            context: recoveryContext,
            persistence: Journal.recoveryPersistence(
                binding: binding,
                persistence: persistence
            )
        )
    }

    private func makePublicationRecoveryContext(
        relaySelection: Alpha.PostManifestRelaySelectionValidation
    ) throws -> Journal.Context {
        try .init(
            publicationContext: ControlBridge.Context(
                validating: completeManifest,
                against: bootstrap
            ),
            relaySelection: relaySelection
        )
    }

    func makeCodingLimits(
        _ capabilities: Runtime.PostManifestRelayCapabilities
    ) throws -> Nostr.RelayMessageCodingLimits {
        try capabilities.validateResourceLimits()
        // Foundation may escape one UTF-8 byte into as many as three JSON
        // bytes. Include the surrounding quotes so the declared raw-byte
        // limit remains sufficient for every valid subscription identifier.
        let maximumEncodedSubscriptionIdentifierByteCount =
            capabilities.maximumSubscriptionIdentifierByteCount * 3 + 2
        let fixedComponents = [
            Data("[\"EVENT\",".utf8).count,
            maximumEncodedSubscriptionIdentifierByteCount,
            1,
            Alpha.nip59MaximumGiftWrapJSONByteCount,
            1,
        ]
        var inboundFrameByteCount = 0
        for component in fixedComponents {
            let addition = inboundFrameByteCount.addingReportingOverflow(
                component
            )
            guard !addition.overflow else {
                throw Runtime.Failure.invalidStateTransition
            }
            inboundFrameByteCount = addition.partialValue
        }
        return try .init(
            maximumFrameByteCount: max(
                inboundFrameByteCount,
                Alpha.nip59MaximumPublicationFrameByteCount
            ),
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: (try Transport.codingLimits).event
        )
    }

    func makeAdmissionContext(
        _ capabilities: Runtime.PostManifestRuntimeCapabilities
    ) -> Alpha.PostManifestAdmissionJournal.Context {
        var bindings: [Alpha.PostManifestAdmissionJournal.RecipientBinding] = [
            .init(
                channel: .control,
                eventIdentity: Array(
                    capabilities.mailboxes.localControlRecipientSigningKey
                        .bip340VerificationKey.rawRepresentation
                )
            ),
        ]
        if case let .conductor(keys) = capabilities.mailboxes.anonymous {
            bindings.append(contentsOf: keys.map {
                .init(
                    channel: .anonymous,
                    eventIdentity: Array(
                        $0.bip340VerificationKey.rawRepresentation
                    )
                )
            })
        }
        return .init(bootstrap: bootstrap, recipientBindings: bindings)
    }

    static func makeLayerTimestamps(
        _ value: Runtime.PostManifestLayerTimestamps
    ) throws -> Transport.LayerTimestamps {
        try .init(
            phaseStartUnixSeconds: value.phaseStartUnixSeconds,
            currentUnixSeconds: value.currentUnixSeconds,
            sealCreatedAt: value.sealCreatedAt,
            giftWrapCreatedAt: value.giftWrapCreatedAt
        )
    }

    static func makeTimestampRequest(
        recipientEventIdentity: Data?,
        phase: OpalFusion.Mosaic.Attempt.Phase,
        sequence: UInt64,
        expiryUnixSeconds: UInt64,
        deadlines: Alpha.DeadlineSchedule
    ) throws -> Runtime.PostManifestTimestampRequest {
        .init(
            recipientEventIdentity: recipientEventIdentity,
            phase: try publicPhase(phase),
            sequence: sequence,
            phaseStartUnixSeconds: deadlines.phaseStart,
            expiryUnixSeconds: expiryUnixSeconds
        )
    }

    static func publicPhase(
        _ phase: OpalFusion.Mosaic.Attempt.Phase
    ) throws -> Runtime.Phase {
        switch phase {
        case .walletReservation: .walletReservation
        case .groupedCommitment: .groupedCommitment
        case .anonymousComponentSubmission: .anonymousComponentSubmission
        case .transcriptAgreement: .transcriptAgreement
        case .bchSigning: .bchSigning
        case .discovery, .candidateSetAgreement,
             .controlRosterAgreement, .roleSelection, .manifestAgreement:
            throw Runtime.Failure.invalidStateTransition
        }
    }

    private static func publicPurpose(
        _ purpose: AttemptTransportOwner.RoutePurpose
    ) -> Runtime.PostManifestRoutePurpose {
        switch purpose {
        case .inboundControl: .inboundControl
        case .inboundAnonymous: .inboundAnonymous
        case .outboundControl: .outboundControl
        case .outboundAnonymousComponents:
            .outboundAnonymousComponents
        case .outboundAnonymousBCHSignatures:
            .outboundAnonymousBCHSignatures
        }
    }
}
#endif
