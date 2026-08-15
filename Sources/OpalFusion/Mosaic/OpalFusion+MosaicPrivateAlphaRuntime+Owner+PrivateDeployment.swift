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
        return try stage { candidate in
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
              case let .discovery(_, _, events, beacons) = try formationState()
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
            var normalized = events
            normalized[index] = event
            let keyed = try normalized.map {
                ($0, try $0.decodeCanonicalNostrEvent().publicKey
                    .rawRepresentation)
            }
            normalized = keyed.sorted {
                $0.1.lexicographicallyPrecedes($1.1)
            }.map(\.0)
            return try stage { candidate in
                candidate.preManifestDocuments.removeLast(events.count)
                candidate.preManifestDocuments += try normalized.map {
                    try $0.canonicalRecoveryBytes()
                }
            }
        }
        return try stageSortedEvent(event, replacing: events.count)
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
        return try stage { candidate in
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
              case let .candidateSetAgreement(_, events, _) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stageSortedEvent(event, replacing: events.count)
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
            advancingTo: .admission
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
              case let .admission(_, _, events, _) = try formationState()
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stageSortedEvent(event, replacing: events.count)
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
            advancingTo: .controlRosterAgreement
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
              case let .controlRosterAgreement(_, events, _) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stageSortedEvent(event, replacing: events.count)
    }

    @_spi(MosaicPrivateAlpha)
    public func completeRoleCommitments()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .controlRosterAgreement(
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
            advancingTo: .roleElection
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
              case let .roleElection(_, _, events, _) = try formationState()
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stageSortedEvent(event, replacing: events.count)
    }

    @_spi(MosaicPrivateAlpha)
    public func completeRoleElection()
        throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        guard !loadedRecoveryNeedsDirective,
              case let .roleElection(
                  _,
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
            advancingTo: .nonceAllocation
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
              case .nonceAllocationPending = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stage { candidate in
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
              case .nonceAllocationAccepted = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stage { candidate in
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
              case .manifestProposalPending = try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stage { candidate in
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
              case let .manifestSignatures(_, events, _) =
                try formationState() else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try stageSortedEvent(event, replacing: events.count)
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
        let proof = try Runtime.restorePrivateDeploymentProof(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            canonicalDocuments: state.preManifestDocuments
                + [Data(completeManifest.canonicalBytes)]
        )
        return try stage { candidate in
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
        return try OpalFusion.MosaicPrivateAlphaRuntime
            .restorePrivateDeploymentFormation(
                discoveryEpochStartUnixSeconds:
                    state.discoveryEpochStartUnixSeconds,
                phase: state.phase,
                canonicalDocuments: state.preManifestDocuments
            )
    }

    private func stageSortedEvent(
        _ event: OpalFusion.MosaicPrivateAlphaRuntime.PrivateDeploymentEvent,
        replacing existingEventCount: Int
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
        let records = try Array(
            state.preManifestDocuments.suffix(existingEventCount)
        ).map(Runtime.PrivateDeploymentEvent.decodeRecoveryBytes) + [event]
        let keyed = try records.map {
            ($0, try $0.decodeCanonicalNostrEvent().publicKey.rawRepresentation)
        }
        let sorted = keyed.sorted {
            $0.1.lexicographicallyPrecedes($1.1)
        }
        for index in sorted.indices.dropFirst() {
            guard sorted[index - 1].1 != sorted[index].1 else {
                throw Runtime.Failure.invalidPrivateDeploymentProof
            }
        }
        return try stage { candidate in
            candidate.preManifestDocuments.removeLast(existingEventCount)
            candidate.preManifestDocuments += try sorted.map {
                try $0.0.canonicalRecoveryBytes()
            }
        }
    }

    func receivedPreManifestConflictStep(
        for event: OpalFusion.MosaicPrivateAlphaRuntime
            .PrivateDeploymentEvent
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step? {
        guard !loadedRecoveryNeedsDirective,
              state.manifestState == .forming,
              state.preManifestAbortCause == .none,
              state.terminalState == .active,
              let conflict = try state.preManifestConflict(for: event) else {
            return nil
        }
        guard conflict.isSemanticConflict else {
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
              state.terminalState == .active,
              state.provesPreManifestInvalidTransition(event) else {
            return nil
        }
        return try stage { candidate in
            candidate.preManifestAbortCause =
                .invalidAuthenticatedMessage(event)
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
                  guard let accepted = try? OpalFusion
                    .MosaicPrivateAlphaRuntime.PrivateDeploymentEvent
                    .decodeRecoveryBytes($0) else {
                      return false
                  }
                  return accepted.canonicalEventBytes
                    == event.canonicalEventBytes
              }) else {
            return nil
        }
        return .ignoredDuplicate(state.phase)
    }

    private func stageReplacingCurrentGroup(
        _ eventCount: Int,
        with normalizedRecords: [Data],
        advancingTo phase: OpalFusion.MosaicPrivateAlphaRuntime.Phase
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Step {
        try stage { candidate in
            candidate.preManifestDocuments.removeLast(eventCount)
            candidate.preManifestDocuments += normalizedRecords
            candidate.phase = phase
        }
    }
}
#endif
