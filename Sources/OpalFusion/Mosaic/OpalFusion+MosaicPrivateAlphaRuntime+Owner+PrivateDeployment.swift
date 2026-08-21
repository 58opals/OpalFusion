// OpalFusion+MosaicPrivateAlphaRuntime+Owner+PrivateDeployment.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime.Owner {
    @_spi(MosaicPrivateAlpha)
    public func resumePrivateDeployment(
        _ continuation: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentContinuation
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard loadedRecoveryNeedsDirective,
              continuation.binding == state.binding,
              continuation.phase == state.phase else {
            throw Runtime.Failure.invalidStateTransition
        }
        switch state.manifestState {
        case .forming:
            guard continuation.proof == nil else {
                throw Runtime.Failure.invalidStateTransition
            }
            _ = try Runtime.restorePrivateDeploymentFormation(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                phase: state.phase,
                canonicalDocuments: state.preManifestDocuments
            )
        case .validated:
            let restored = try Runtime.restorePrivateDeploymentProof(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                canonicalDocuments: state.preManifestDocuments
            )
            guard continuation.proof == restored else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
        }
        loadedRecoveryNeedsDirective = false
        return try nextStep()
    }

    @_spi(MosaicPrivateAlpha)
    public func installPrivateDeploymentContext(
        opaquePoolDocument: Data,
        relaySetDocument: Data
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case .uninitialized = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let pool = try OpalFusion.Mosaic.OpalMainnetAlpha.OpaquePoolDocument
            .decode(from: Array(opaquePoolDocument))
        let relaySet = try OpalFusion.Mosaic.OpalMainnetAlpha.RelaySetDocument
            .decode(from: Array(relaySetDocument))
        guard Data(pool.canonicalBytes) == opaquePoolDocument,
              Data(relaySet.canonicalBytes) == relaySetDocument else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        return try stageValidatedPrivateDeployment(
            formation: .discovery(
                pool: pool,
                relaySet: relaySet,
                events: [],
                beacons: []
            )
        ) { candidate in
            candidate.preManifestDocuments = [
                opaquePoolDocument,
                relaySetDocument,
            ]
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptAvailabilityBeacon(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .discovery(pool, relaySet, events, beacons) =
                try formationState()
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        let decodedEvent = try event.decodeCanonicalNostrEvent()
        let beacon = try Alpha.PreManifestNostrCodec
            .decodeAvailabilityBeacon(
                decodedEvent,
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        if let index = beacons.firstIndex(where: {
            $0.core.discoveryIdentity == beacon.core.discoveryIdentity
        }) {
            let existing = beacons[index]
            guard existing.core.canonicalBytes == beacon.core.canonicalBytes
            else {
                return try stageAuthenticatedEquivocation(event)
            }
            let replacesExisting = beacon.canonicalBytes
                .lexicographicallyPrecedes(existing.canonicalBytes)
                || (beacon.canonicalBytes == existing.canonicalBytes
                    && event.canonicalEventBytes.lexicographicallyPrecedes(
                        events[index].canonicalEventBytes
                    ))
            guard replacesExisting else {
                return .ignoredDuplicate(.discovery)
            }
            var normalizedEvents = events
            var normalizedBeacons = beacons
            normalizedEvents[index] = event
            normalizedBeacons[index] = beacon
            let normalized = try signerOrdered(
                events: normalizedEvents,
                documents: normalizedBeacons
            ) {
                [UInt8]($0.core.discoveryIdentity.rawRepresentation)
            }
            return try stageValidatedPrivateDeployment(
                formation: .discovery(
                    pool: pool,
                    relaySet: relaySet,
                    events: normalized.events,
                    beacons: normalized.documents
                )
            ) { candidate in
                candidate.preManifestDocuments.removeLast(events.count)
                candidate.preManifestDocuments += try normalized.events.map {
                    try $0.canonicalRecoveryBytes()
                }
            }
        }
        let normalized = try signerOrdered(
            appending: event,
            document: beacon,
            to: events,
            documents: beacons
        ) {
            [UInt8]($0.core.discoveryIdentity.rawRepresentation)
        }
        return try stageValidatedPrivateDeployment(
            formation: .discovery(
                pool: pool,
                relaySet: relaySet,
                events: normalized.events,
                beacons: normalized.documents
            )
        ) { candidate in
            candidate.preManifestDocuments.removeLast(events.count)
            candidate.preManifestDocuments += try normalized.events.map {
                try $0.canonicalRecoveryBytes()
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeDiscovery(currentUnixSeconds: UInt64)
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .discovery(pool, relaySet, events, beacons) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let deadlines = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentPolicy.frozen.preManifestDeadlines(
                forEpochStartingAt:
                    state.discoveryEpochStartUnixSeconds
            )
        guard currentUnixSeconds >= deadlines.beaconCutoff else {
            throw Runtime.Failure.invalidStateTransition
        }
        let selection = try OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateSelectionValidation(
                beacons: beacons,
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                opaquePool: pool,
                relaySet: relaySet
            )
        let selectedEvents = try selection.selectedBeacons.map { beacon in
            guard let event = zip(events, beacons).first(where: {
                $0.1 == beacon
            })?.0 else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
            return event
        }
        return try stageValidatedPrivateDeployment(
            formation: .candidateSetAgreement(
                selection: selection,
                events: [],
                acknowledgements: []
            ),
            attempt: try advancingAttempt(
                with: .discoveryCompleted(
                    candidateCount: selection.selectedBeacons.count
                )
            )
        ) { candidate in
            candidate.preManifestDocuments = Array(
                candidate.preManifestDocuments.prefix(2)
            ) + (try selectedEvents.map { try $0.canonicalRecoveryBytes() })
            candidate.phase = .candidateSetAgreement
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptCandidateSetAcknowledgement(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let conflict = try receivedPreManifestConflictStep(for: event) {
            return conflict
        }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .candidateSetAgreement(
                  selection,
                  events,
                  acknowledgements
              ) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let acknowledgement = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeCandidateSetAcknowledgement(
                event.decodeCanonicalNostrEvent(),
                candidateSelection: selection,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        let normalized = try signerOrdered(
            appending: event,
            document: acknowledgement,
            to: events,
            documents: acknowledgements
        ) {
            [UInt8]($0.signerDiscoveryIdentity.rawRepresentation)
        }
        return try stageValidatedPrivateDeployment(
            formation: .candidateSetAgreement(
                selection: selection,
                events: normalized.events,
                acknowledgements: normalized.documents
            )
        ) { candidate in
            candidate.preManifestDocuments.removeLast(events.count)
            candidate.preManifestDocuments += try normalized.events.map {
                try $0.canonicalRecoveryBytes()
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeCandidateSetAgreement()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .candidateSetAgreement(
                  selection,
                  events,
                  acknowledgements
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let set = try OpalFusion.Mosaic.OpalMainnetAlpha
            .CandidateSetAcknowledgementSetDocument(
                acknowledgements: acknowledgements,
                candidateSelection: selection
            )
        let normalized = try set.acknowledgements.map { acknowledgement in
            guard let event = zip(events, acknowledgements).first(where: {
                $0.1 == acknowledgement
            })?.0 else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
            return try event.canonicalRecoveryBytes()
        }
        return try stageReplacingCurrentGroup(
            events.count,
            with: normalized,
            advancingTo: .admission,
            formation: .admission(
                selection: selection,
                acknowledgementSet: set,
                events: [],
                admissions: []
            ),
            attempt: try advancingAttempt(
                with: .candidateSetAgreementValidated
            )
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptCandidateAdmission(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let conflict = try receivedPreManifestConflictStep(for: event) {
            return conflict
        }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .admission(
                  selection,
                  acknowledgementSet,
                  events,
                  admissions
              ) = try formationState()
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        let admission = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeCandidateAdmission(
                event.decodeCanonicalNostrEvent(),
                candidateSelection: selection,
                acknowledgementSet: acknowledgementSet,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        let normalized = try signerOrdered(
            appending: event,
            document: admission,
            to: events,
            documents: admissions
        ) {
            [UInt8]($0.discoveryIdentity.rawRepresentation)
        }
        return try stageValidatedPrivateDeployment(
            formation: .admission(
                selection: selection,
                acknowledgementSet: acknowledgementSet,
                events: normalized.events,
                admissions: normalized.documents
            )
        ) { candidate in
            candidate.preManifestDocuments.removeLast(events.count)
            candidate.preManifestDocuments += try normalized.events.map {
                try $0.canonicalRecoveryBytes()
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeCandidateAdmission()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .admission(
                  selection,
                  acknowledgementSet,
                  events,
                  admissions
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let roster = try OpalFusion.Mosaic.OpalMainnetAlpha
            .ControlRosterValidation(
                admissions: admissions,
                candidateSelection: selection,
                acknowledgementSet: acknowledgementSet
            )
        let normalized = try roster.admissions.map { admission in
            guard let event = zip(events, admissions).first(where: {
                $0.1 == admission
            })?.0 else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
            return try event.canonicalRecoveryBytes()
        }
        return try stageReplacingCurrentGroup(
            events.count,
            with: normalized,
            advancingTo: .controlRosterAgreement,
            formation: .controlRosterAgreement(
                candidateSelection: selection,
                controlRoster: roster,
                events: [],
                commitments: []
            ),
            attempt: try advancingAttempt(
                with: .controlRosterValidated(
                    roster.controlRosterBinding
                )
            )
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptRoleCommitment(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let conflict = try receivedPreManifestConflictStep(for: event) {
            return conflict
        }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .controlRosterAgreement(
                  candidateSelection,
                  controlRoster,
                  events,
                  commitments
              ) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let commitment = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeRoleCommitment(
                event.decodeCanonicalNostrEvent(),
                controlRoster: controlRoster,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        let normalized = try signerOrdered(
            appending: event,
            document: commitment,
            to: events,
            documents: commitments
        ) { $0.candidate.validatedBytes }
        return try stageValidatedPrivateDeployment(
            formation: .controlRosterAgreement(
                candidateSelection: candidateSelection,
                controlRoster: controlRoster,
                events: normalized.events,
                commitments: normalized.documents
            )
        ) { candidate in
            candidate.preManifestDocuments.removeLast(events.count)
            candidate.preManifestDocuments += try normalized.events.map {
                try $0.canonicalRecoveryBytes()
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeRoleCommitments()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .controlRosterAgreement(
                  candidateSelection,
                  controlRoster,
                  events,
                  commitments
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let set = try OpalFusion.Mosaic.Attempt.RoleCommitmentSet(
            controlRoster: controlRoster.controlRosterBinding,
            commitments: commitments
        )
        let normalized = try set.commitments.map { commitment in
            guard let event = zip(events, commitments).first(where: {
                $0.1 == commitment
            })?.0 else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
            return try event.canonicalRecoveryBytes()
        }
        return try stageReplacingCurrentGroup(
            events.count,
            with: normalized,
            advancingTo: .roleElection,
            formation: .roleElection(
                candidateSelection: candidateSelection,
                controlRoster: controlRoster,
                commitmentSet: set,
                events: [],
                reveals: []
            ),
            attempt: try advancingAttempt(
                with: .roleCommitmentsReceived(set.commitments)
            )
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptRoleReveal(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let conflict = try receivedPreManifestConflictStep(for: event) {
            return conflict
        }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .roleElection(
                  candidateSelection,
                  controlRoster,
                  commitmentSet,
                  events,
                  reveals
              ) = try formationState()
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        let reveal = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeRoleReveal(
                event.decodeCanonicalNostrEvent(),
                controlRoster: controlRoster,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        let normalized = try signerOrdered(
            appending: event,
            document: reveal,
            to: events,
            documents: reveals
        ) { $0.candidate.validatedBytes }
        return try stageValidatedPrivateDeployment(
            formation: .roleElection(
                candidateSelection: candidateSelection,
                controlRoster: controlRoster,
                commitmentSet: commitmentSet,
                events: normalized.events,
                reveals: normalized.documents
            )
        ) { candidate in
            candidate.preManifestDocuments.removeLast(events.count)
            candidate.preManifestDocuments += try normalized.events.map {
                try $0.canonicalRecoveryBytes()
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeRoleElection()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .roleElection(
                  candidateSelection,
                  controlRoster,
                  commitmentSet,
                  events,
                  reveals
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let seed = try OpalFusion.Mosaic.Attempt.RoleSeedValidation(
            profile: .opalMainnetAlpha,
            commitmentSet: commitmentSet,
            reveals: reveals,
            using: OpalFusion.Mosaic.OpalMainnetAlpha.RoleSeedValidator()
        )
        let normalized = try seed.revealSet.reveals.map { reveal in
            guard let event = zip(events, reveals).first(where: {
                $0.1 == reveal
            })?.0 else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
            return try event.canonicalRecoveryBytes()
        }
        return try stageReplacingCurrentGroup(
            events.count,
            with: normalized,
            advancingTo: .nonceAllocation,
            formation: .nonceAllocationPending(
                candidateSelection: candidateSelection,
                controlRoster: controlRoster,
                roleElection: try OpalFusion.Mosaic.Attempt
                    .RoleElectionResult(
                        profile: .opalMainnetAlpha,
                        commitmentSet: commitmentSet,
                        validation: seed
                    )
            ),
            attempt: try advancingAttempt(
                with: .roleElectionValidated(seed)
            )
        )
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptContributorNonceAllocation(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let conflict = try receivedPreManifestConflictStep(for: event) {
            return conflict
        }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .nonceAllocationPending(
                  candidateSelection,
                  controlRoster,
                  roleElection
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let nonceAllocation = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec
            .decodeContributorNonceAllocation(
                event.decodeCanonicalNostrEvent(),
                controlRoster: controlRoster,
                roleElection: roleElection,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        return try stageValidatedPrivateDeployment(
            formation: .nonceAllocationAccepted(
                candidateSelection: candidateSelection,
                controlRoster: controlRoster,
                roleElection: roleElection,
                nonceAllocation: nonceAllocation
            )
        ) { candidate in
            candidate.preManifestDocuments.append(
                try event.canonicalRecoveryBytes()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeNonceAllocation()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .nonceAllocationAccepted(
                  candidateSelection,
                  controlRoster,
                  roleElection,
                  nonceAllocation
              ) = try formationState(),
              state.preManifestDocuments.count >= 2 else {
            throw Runtime.Failure.invalidStateTransition
        }
        let pool = try OpalFusion.Mosaic.OpalMainnetAlpha.OpaquePoolDocument
            .decode(from: Array(state.preManifestDocuments[0]))
        let relaySet = try OpalFusion.Mosaic.OpalMainnetAlpha.RelaySetDocument
            .decode(from: Array(state.preManifestDocuments[1]))
        guard Data(pool.canonicalBytes) == state.preManifestDocuments[0],
              Data(relaySet.canonicalBytes) == state.preManifestDocuments[1],
              pool.opaqueIdentifier
                == candidateSelection.opaquePoolIdentifier,
              relaySet.digest == candidateSelection.relaySetDigest else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        let nextFormation = Runtime.PrivateDeploymentFormationState
            .manifestProposalPending(
                pool: pool,
                relaySet: relaySet,
                candidateSelection: candidateSelection,
                controlRoster: controlRoster,
                roleElection: roleElection,
                nonceAllocation: nonceAllocation
        )
        return try stageValidatedPrivateDeployment(
            formation: nextFormation
        ) { candidate in
            candidate.phase = .manifestAgreement
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptManifestProposal(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let conflict = try receivedPreManifestConflictStep(for: event) {
            return conflict
        }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .manifestProposalPending(
                  pool,
                  relaySet,
                  candidateSelection,
                  controlRoster,
                  roleElection,
                  nonceAllocation
              ) = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let proposalContext = try OpalFusion.Mosaic.OpalMainnetAlpha
            .ManifestProposalContext(
                roleElection: roleElection,
                candidateSetDigest: candidateSelection.candidateSetDigest,
                opaquePoolIdentifier: pool.opaqueIdentifier
            )
        let decodedEvent = try event.decodeCanonicalNostrEvent()
        let manifestCore = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeManifestProposalCandidate(
                decodedEvent,
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                proposalContext: proposalContext,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        let manifestValidation = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestValidation(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                core: manifestCore,
                candidateSelection: candidateSelection,
                controlRoster: controlRoster,
                roleElection: roleElection,
                opaquePool: pool,
                relaySet: relaySet,
                nonceAllocation: nonceAllocation
            )
        let proposal = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PrivateDeploymentManifestProposalValidation(
                manifest: manifestValidation
            )
        guard try OpalFusion.Mosaic.OpalMainnetAlpha.PreManifestNostrCodec
                .decodeManifestProposal(
                    decodedEvent,
                    proposal: proposal,
                    currentUnixSeconds: event.acceptedAtUnixSeconds
                ) == manifestCore else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        return try stageValidatedPrivateDeployment(
            formation: .manifestSignatures(
                proposal: proposal,
                events: [],
                signatures: []
            )
        ) { candidate in
            candidate.preManifestDocuments.append(
                try event.canonicalRecoveryBytes()
            )
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func acceptManifestSignature(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        if let ignored = ignoredDuplicateStep(for: event) { return ignored }
        if let conflict = try receivedPreManifestConflictStep(for: event) {
            return conflict
        }
        if let invalid = try receivedPreManifestInvalidTransitionStep(
            for: event
        ) { return invalid }
        guard !loadedRecoveryNeedsDirective,
              case let .manifestSignatures(
                  proposal,
                  events,
                  signatures
              ) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let signature = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeManifestSignature(
                event.decodeCanonicalNostrEvent(),
                proposal: proposal,
                currentUnixSeconds: event.acceptedAtUnixSeconds
            )
        let normalized = try signerOrdered(
            appending: event,
            document: signature,
            to: events,
            documents: signatures
        ) { $0.signature.signer.validatedBytes }
        return try stageValidatedPrivateDeployment(
            formation: .manifestSignatures(
                proposal: proposal,
                events: normalized.events,
                signatures: normalized.documents
            )
        ) { candidate in
            candidate.preManifestDocuments.removeLast(events.count)
            candidate.preManifestDocuments += try normalized.events.map {
                try $0.canonicalRecoveryBytes()
            }
        }
    }

    @_spi(MosaicPrivateAlpha)
    public func completeManifestAgreement()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .manifestSignatures(proposal, _, signatures) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        let completeManifest = try OpalFusion.Mosaic.OpalMainnetAlpha
            .RoundManifest(
                core: proposal.manifest.core,
                signatures: signatures.map(\.signature)
            )
        let canonicalDocuments = state.preManifestDocuments
            + [Data(completeManifest.canonicalBytes)]
        let proof: Runtime.PrivateDeploymentProof
        if let cachedAttempt {
            guard case .manifestAgreement = cachedAttempt.state else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
            proof = .init(
                validatedAttempt: cachedAttempt,
                proposalValidation: proposal,
                completeManifest: completeManifest,
                canonicalDocuments: canonicalDocuments
            )
        } else {
            proof = try Runtime.restorePrivateDeploymentProof(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                canonicalDocuments: canonicalDocuments
            )
        }
        return try stageValidatedPrivateDeployment(formation: nil) {
            candidate in
            candidate.preManifestDocuments = proof.canonicalDocuments
            candidate.manifestState = .validated(
                privateManifestProposalBytes: Data(
                    proof.proposalValidation.canonicalBody
                ),
                completeManifestBytes: Data(
                    proof.completeManifest.canonicalBytes
                )
            )
            candidate.phase = .walletReservation
        }
    }

    func formationState() throws
        -> OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentFormationState {
        guard state.preManifestAbortCause == .none else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .invalidStateTransition
        }
        if let cachedFormationState {
            return cachedFormationState
        }
        let restored = try OpalFusion.MosaicPrivateAlphaRuntime
            .restorePrivateDeploymentFormation(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                phase: state.phase,
                canonicalDocuments: state.preManifestDocuments
            )
        cachedFormationState = restored
        return restored
    }

    func signerOrdered<Document>(
        appending event: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        document: Document,
        to events: [OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent],
        documents: [Document],
        signerIdentity: (Document) -> [UInt8]
    ) throws -> (
        events: [OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent],
        documents: [Document]
    ) {
        try signerOrdered(
            events: events + [event],
            documents: documents + [document],
            signerIdentity: signerIdentity
        )
    }

    func signerOrdered<Document>(
        events: [OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent],
        documents: [Document],
        signerIdentity: (Document) -> [UInt8]
    ) throws -> (
        events: [OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent],
        documents: [Document]
    ) {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard events.count == documents.count else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        let sorted = zip(events, documents).map {
            (event: $0.0, document: $0.1, signer: signerIdentity($0.1))
        }.sorted {
            $0.signer.lexicographicallyPrecedes($1.signer)
        }
        for index in sorted.indices.dropFirst() {
            guard sorted[index - 1].signer != sorted[index].signer else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
        }
        return (sorted.map(\.event), sorted.map(\.document))
    }

    func receivedPreManifestConflictStep(
        for event: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step? {
        guard !loadedRecoveryNeedsDirective,
              state.manifestState == .forming,
              state.preManifestAbortCause == .none,
              state.terminalState == .active else {
            return nil
        }
        let formation = try formationState()
        let envelope = try decodeTimelyPreManifestEnvelope(event)
        guard envelope.payload.payloadKind
                == expectedPayloadKind(for: formation) else {
            guard let conflict = try state.preManifestConflict(for: event)
            else {
                return nil
            }
            guard conflict.isSemanticConflict else {
                return .ignoredDuplicate(state.phase)
            }
            return try stageAuthenticatedEquivocation(event)
        }
        guard let isSemanticConflict = try currentGroupSemanticConflict(
            for: event,
            envelope: envelope,
            formation: formation
        ) else {
            return nil
        }
        guard isSemanticConflict else {
            return .ignoredDuplicate(state.phase)
        }
        return try stageAuthenticatedEquivocation(event)
    }

    func receivedPreManifestInvalidTransitionStep(
        for event: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step? {
        guard !loadedRecoveryNeedsDirective,
              state.manifestState == .forming,
              state.preManifestAbortCause == .none,
              state.terminalState == .active else {
            return nil
        }
        let formation = try formationState()
        let payload = try decodeTimelyPreManifestEnvelope(event).payload
        guard payload.payloadKind != expectedPayloadKind(for: formation),
              payload.payloadKind != .abort,
              payload.payloadKind != .completion,
              signerIsRecognized(
                  [UInt8](payload.signerIdentity.rawRepresentation),
                  in: formation
              ) else {
            return nil
        }
        return try stage { candidate in
            candidate.preManifestAbortCause =
                .invalidAuthenticatedMessage(event)
        }
    }

    private func decodeTimelyPreManifestEnvelope(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent
    ) throws -> (
        event: OpalFusion.Mosaic.NostrNamespace.Event,
        payload: OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrPayloadDocument
    ) {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let nostrEvent = try event.decodeCanonicalNostrEvent()
        let payload = try OpalFusion.Mosaic.OpalMainnetAlpha
            .PreManifestNostrCodec.decodeCanonicalEnvelope(nostrEvent)
        guard payload.discoveryEpochStartUnixSeconds
                == state.discoveryEpochStartUnixSeconds,
              nostrEvent.template.createdAt <= event.acceptedAtUnixSeconds,
              event.acceptedAtUnixSeconds <= payload.expiryUnixSeconds else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        return (nostrEvent, payload)
    }

    private func expectedPayloadKind(
        for formation: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentFormationState
    ) -> OpalFusion.Mosaic.OpalMainnetAlpha
        .PrivateDeploymentNostrSelector.PayloadKind? {
        switch formation {
        case .uninitialized, .discovery:
            .availabilityBeacon
        case .candidateSetAgreement:
            .candidateSetAcknowledgement
        case .admission:
            .candidateAdmission
        case .controlRosterAgreement:
            .roleCommitment
        case .roleElection:
            .roleReveal
        case .nonceAllocationPending:
            .contributorNonceAllocation
        case .nonceAllocationAccepted:
            nil
        case .manifestProposalPending:
            .manifestProposal
        case .manifestSignatures:
            .manifestSignature
        }
    }

    private func signerIsRecognized(
        _ signer: [UInt8],
        in formation: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentFormationState
    ) -> Bool {
        switch formation {
        case .uninitialized:
            false
        case let .discovery(_, _, _, beacons):
            beacons.contains {
                [UInt8]($0.core.discoveryIdentity.rawRepresentation) == signer
            }
        case let .candidateSetAgreement(selection, _, _),
             let .admission(selection, _, _, _):
            selection.selectedDiscoveryIdentities.contains(signer)
        case let .controlRosterAgreement(_, roster, _, _),
             let .roleElection(_, roster, _, _, _),
             let .nonceAllocationPending(_, roster, _),
             let .nonceAllocationAccepted(_, roster, _, _),
             let .manifestProposalPending(_, _, _, roster, _, _):
            roster.controlRosterBinding.controlIdentities.contains {
                $0.validatedBytes == signer
            }
        case let .manifestSignatures(proposal, _, _):
            proposal.manifest.core.roster.controlIdentities.contains {
                $0.validatedBytes == signer
            }
        }
    }

    private func currentGroupSemanticConflict(
        for event: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent,
        envelope: (
            event: OpalFusion.Mosaic.NostrNamespace.Event,
            payload: OpalFusion.Mosaic.OpalMainnetAlpha
                .PreManifestNostrPayloadDocument
        ),
        formation: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentFormationState
    ) throws -> Bool? {
        typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let signer = [UInt8](
            envelope.payload.signerIdentity.rawRepresentation
        )
        func compare<Document>(
            events: [Runtime.PrivateDeploymentEvent],
            documents: [Document],
            signerIdentity: (Document) -> [UInt8],
            canonicalPayload: (Document) throws -> [UInt8]
        ) throws -> Bool? {
            guard events.count == documents.count else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
            guard let index = documents.firstIndex(where: {
                signerIdentity($0) == signer
            }) else {
                return nil
            }
            guard events[index].canonicalEventBytes
                    != event.canonicalEventBytes else {
                return false
            }
            return try canonicalPayload(documents[index])
                != envelope.payload.canonicalBytes
        }
        switch formation {
        case let .discovery(_, _, events, beacons):
            guard let index = beacons.firstIndex(where: {
                [UInt8]($0.core.discoveryIdentity.rawRepresentation) == signer
            }) else {
                return nil
            }
            guard events.indices.contains(index),
                  events[index].canonicalEventBytes
                    != event.canonicalEventBytes else {
                return false
            }
            let incoming = try Alpha.PreManifestNostrCodec
                .decodeAvailabilityBeacon(
                    envelope.event,
                    discoveryEpochStartUnixSeconds:
                        state.discoveryEpochStartUnixSeconds,
                    currentUnixSeconds: event.acceptedAtUnixSeconds
                )
            return beacons[index].core.canonicalBytes
                != incoming.core.canonicalBytes
        case let .candidateSetAgreement(_, events, documents):
            return try compare(
                events: events,
                documents: documents,
                signerIdentity: {
                    [UInt8]($0.signerDiscoveryIdentity.rawRepresentation)
                },
                canonicalPayload: {
                    try Alpha.PreManifestNostrPayloadDocument
                        .makeCandidateSetAcknowledgement($0).canonicalBytes
                }
            )
        case let .admission(_, _, events, documents):
            return try compare(
                events: events,
                documents: documents,
                signerIdentity: {
                    [UInt8]($0.discoveryIdentity.rawRepresentation)
                },
                canonicalPayload: {
                    try Alpha.PreManifestNostrPayloadDocument
                        .makeCandidateAdmission($0).canonicalBytes
                }
            )
        case let .controlRosterAgreement(_, roster, events, documents):
            return try compare(
                events: events,
                documents: documents,
                signerIdentity: { $0.candidate.validatedBytes },
                canonicalPayload: {
                    try Alpha.PreManifestNostrPayloadDocument
                        .makeRoleCommitment($0, controlRoster: roster)
                        .canonicalBytes
                }
            )
        case let .roleElection(_, roster, _, events, documents):
            return try compare(
                events: events,
                documents: documents,
                signerIdentity: { $0.candidate.validatedBytes },
                canonicalPayload: {
                    try Alpha.PreManifestNostrPayloadDocument
                        .makeRoleReveal($0, controlRoster: roster)
                        .canonicalBytes
                }
            )
        case let .manifestSignatures(proposal, events, documents):
            return try compare(
                events: events,
                documents: documents,
                signerIdentity: { $0.signature.signer.validatedBytes },
                canonicalPayload: {
                    try Alpha.PreManifestNostrPayloadDocument
                        .makeManifestSignature(
                            $0.signature,
                            proposal: proposal
                        ).canonicalBytes
                }
            )
        case .uninitialized,
             .nonceAllocationPending,
             .nonceAllocationAccepted,
             .manifestProposalPending:
            return nil
        }
    }

    private func stageAuthenticatedEquivocation(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard let conflict = try state.preManifestConflict(for: event),
              conflict.isSemanticConflict else {
            throw Runtime.Failure.invalidPrivateDeploymentProof
        }
        var substituted = state
        substituted.preManifestDocuments[conflict.storedIndex] =
            try event.canonicalRecoveryBytes()
        try substituted.validate()
        return try stage { candidate in
            candidate.preManifestAbortCause = .equivocation(event)
        }
    }

    private func ignoredDuplicateStep(
        for event: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent
    ) -> OpalFusion.MosaicPrivateAlphaRuntime.Step? {
        guard !loadedRecoveryNeedsDirective,
              state.manifestState == .forming,
              state.terminalState == .active,
              state.preManifestDocuments.dropFirst(2).contains(where: {
                  let accepted = try? OpalFusion.MosaicPrivateAlphaRuntime
                    .PrivateDeploymentEvent.canonicalEventBytes(
                        fromValidatedRecoveryBytes: $0
                    )
                  return accepted
                    == event.canonicalEventBytes
              }) else {
            return nil
        }
        return .ignoredDuplicate(state.phase)
    }

    private func stageReplacingCurrentGroup(
        _ eventCount: Int,
        with normalizedRecords: [Data],
        advancingTo phase: OpalFusion.MosaicPrivateAlphaRuntime.Phase,
        formation: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentFormationState,
        attempt: OpalFusion.Mosaic.Attempt?
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        try stageValidatedPrivateDeployment(
            formation: formation,
            attempt: attempt
        ) { candidate in
            candidate.preManifestDocuments.removeLast(eventCount)
            candidate.preManifestDocuments += normalizedRecords
            candidate.phase = phase
        }
    }

    private func advancingAttempt(
        with input: OpalFusion.Mosaic.Attempt.Input
    ) throws -> OpalFusion.Mosaic.Attempt? {
        guard var attempt = cachedAttempt else { return nil }
        guard attempt.apply(input: input).isEmpty else {
            throw OpalFusion.MosaicPrivateAlphaRuntime.Failure
                .invalidPrivateDeploymentProof
        }
        return attempt
    }
}
#endif
