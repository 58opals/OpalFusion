// MosaicPrivateAlphaRuntimeSPIValidator+PreManifestAbort.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

extension MosaicPrivateAlphaRuntimeSPIValidator {
    @Test("Persist recover and publish a package-derived equivocation abort")
    func persistRecoverAndPublishPreManifestEquivocationAbort() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeAbortBinding(seed: 0x44)
        let storedEvent = fixture.admissionEvents[0]
        let storedRecord = try storedEvent.canonicalRecoveryBytes()
        let storedIndex = try #require(
            fixture.proof.canonicalDocuments.firstIndex(of: storedRecord)
        )
        let state = Runtime.RecoveryState(
            binding: binding,
            revision: 20,
            discoveryEpochStartUnixSeconds: fixture.epoch,
            phase: .admission,
            preManifestDocuments: Array(
                fixture.proof.canonicalDocuments.prefix(through: storedIndex)
            ),
            preManifestAbortCause: .none,
            manifestState: .forming,
            postManifestJournalState: .uninitialized,
            publicationState: .none,
            terminalState: .active
        )
        try state.validate()
        let originalSnapshot = try state.canonicalBytes()
        let originalSigner = try storedEvent.decodeCanonicalNostrEvent()
            .publicKey
        let signer = fixture.formation.discovery.candidate(
            for: originalSigner
        )
        let rewrapped = try MosaicPrivateDeploymentFixtures
            .rewrapPrivateDeploymentEvent(
                storedEvent,
                using: signer.signingKey,
                createdAtUnixSeconds: fixture.epoch + 92,
                eventAuxiliaryByte: 0xE1
            )
        let duplicateOwner = try await makeResumedAbortOwner(
            snapshot: originalSnapshot,
            binding: binding
        ).owner
        #expect(
            try await duplicateOwner.acceptCandidateAdmission(rewrapped)
                == .ignoredDuplicate(.admission)
        )

        let conflicting = try MosaicPrivateDeploymentFixtures
            .makeConflictingAdmissionEvent(
                formation: fixture.formation,
                replacing: storedEvent,
                createdAtUnixSeconds: fixture.epoch + 92,
                eventAuxiliaryByte: 0xE2
            )
        for rejected in [
            try Runtime.PrivateDeploymentEvent(
                canonicalEventBytes: conflicting.canonicalEventBytes,
                acceptedAtUnixSeconds: fixture.epoch + 91
            ),
            try Runtime.PrivateDeploymentEvent(
                canonicalEventBytes: conflicting.canonicalEventBytes,
                acceptedAtUnixSeconds: fixture.epoch + 121
            ),
        ] {
            let rejectedOwner = try await makeResumedAbortOwner(
                snapshot: originalSnapshot,
                binding: binding
            ).owner
            await #expect(throws: Runtime.Failure
                .invalidPrivateDeploymentProof) {
                _ = try await rejectedOwner.acceptCandidateAdmission(rejected)
            }
            #expect(
                try await rejectedOwner.nextStep() == .awaitingInput(.admission)
            )
        }
        let causeOwner = try await makeResumedAbortOwner(
            snapshot: originalSnapshot,
            binding: binding
        ).owner
        let causeStep = try await causeOwner.acceptCandidateAdmission(
            conflicting
        )
        guard case let .persist(causeTransition) = causeStep else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(try await causeOwner.nextStep() == causeStep)
        let causeNext = try await causeOwner.acknowledgePersistence(
            causeTransition,
            exactReadback: causeTransition.replacementSnapshot
        )
        #expect(causeNext == .awaitingPreManifestAbortSignature(.admission))
        let causeSnapshot = causeTransition.replacementSnapshot
        let causeState = try Runtime.RecoveryState.decode(
            from: causeSnapshot,
            expectedBinding: binding
        )
        #expect(causeState.preManifestAbortCause == .equivocation(conflicting))

        let loaded = try Runtime.loadRecovery(
            from: causeSnapshot,
            expectedBinding: binding
        )
        let recoveredOwner = try Runtime.Owner(claiming: loaded)
        guard case let .recover(.resumePrivateDeployment(continuation)) =
            try await recoveredOwner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(
            try await recoveredOwner.resumePrivateDeployment(continuation)
                == .awaitingPreManifestAbortSignature(.admission)
        )
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await recoveredOwner.acceptCandidateAdmission(
                fixture.admissionEvents[1]
            )
        }

        var duplicateCause = causeState
        duplicateCause.preManifestAbortCause = .equivocation(rewrapped)
        #expect(throws: Runtime.Failure.contradictoryRecoverySnapshot) {
            _ = try Runtime.loadRecovery(
                from: duplicateCause.canonicalBytes(),
                expectedBinding: binding
            )
        }
        var missingPredecessor = causeState
        missingPredecessor.preManifestDocuments.removeLast()
        #expect(throws: Runtime.Failure.contradictoryRecoverySnapshot) {
            _ = try Runtime.loadRecovery(
                from: missingPredecessor.canonicalBytes(),
                expectedBinding: binding
            )
        }
        var substitutedCause = causeState
        substitutedCause.preManifestAbortCause = .equivocation(
            fixture.admissionEvents[1]
        )
        #expect(throws: Runtime.Failure.contradictoryRecoverySnapshot) {
            _ = try Runtime.loadRecovery(
                from: substitutedCause.canonicalBytes(),
                expectedBinding: binding
            )
        }

        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await recoveredOwner.preparePreManifestAbort(
                currentUnixSeconds: fixture.epoch + 91,
                signing: makeAbortSigningCapability(
                    signer.signingKey,
                    documentByte: 0xE3,
                    eventByte: 0xE4
                )
            )
        }
        let abortStep = try await recoveredOwner.preparePreManifestAbort(
            currentUnixSeconds: fixture.epoch + 92,
            signing: makeAbortSigningCapability(
                signer.signingKey,
                documentByte: 0xE5,
                eventByte: 0xE6
            )
        )
        #expect(
            try abortReason(in: abortStep, binding: binding)
                == .equivocation
        )
        let terminalSnapshot = try await persistAndPublishAbort(
            abortStep,
            on: recoveredOwner
        )
        let terminalRecovery = try Runtime.loadRecovery(
            from: terminalSnapshot,
            expectedBinding: binding
        )
        let terminalOwner = try Runtime.Owner(claiming: terminalRecovery)
        guard case let .recover(.terminal(disposition)) =
            try await terminalOwner.nextStep(),
              case .cleanupAuthorized(.aborted, _, _) = disposition else {
            throw Runtime.Failure.terminalEvidenceUnavailable
        }
        let evidence = try await terminalOwner.claimTerminalEvidence()
        #expect(evidence.binding == binding)
    }

    @Test("Derive missing-participant and timeout aborts at frozen boundaries")
    func derivePreManifestDeadlineAbortReasons() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let firstAcknowledgement = try fixture.acknowledgementEvents[0]
            .canonicalRecoveryBytes()
        let acknowledgementStart = try #require(
            fixture.proof.canonicalDocuments.firstIndex(
                of: firstAcknowledgement
            )
        )
        let firstAdmission = try fixture.admissionEvents[0]
            .canonicalRecoveryBytes()
        let admissionStart = try #require(
            fixture.proof.canonicalDocuments.firstIndex(of: firstAdmission)
        )
        let signingKey = fixture.formation.discovery.candidate(
            for: try fixture.beaconEvents[0].decodeCanonicalNostrEvent()
                .publicKey
        ).signingKey
        let boundary = try Runtime.preManifestTimeoutBoundary(
            phase: .candidateSetAgreement,
            discoveryEpochStartUnixSeconds: fixture.epoch
        )

        let incompleteBinding = try makeAbortBinding(seed: 0x51)
        let incompleteState = try makeAbortState(
            binding: incompleteBinding,
            revision: 30,
            epoch: fixture.epoch,
            phase: .candidateSetAgreement,
            documents: Array(
                fixture.proof.canonicalDocuments.prefix(
                    upTo: acknowledgementStart
                )
            )
        )
        let beforeOwner = try await makeResumedAbortOwner(
            snapshot: incompleteState.canonicalBytes(),
            binding: incompleteBinding
        ).owner
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await beforeOwner.preparePreManifestAbort(
                currentUnixSeconds: boundary - 1,
                signing: makeAbortSigningCapability(
                    signingKey,
                    documentByte: 0xA1,
                    eventByte: 0xA2
                )
            )
        }
        let atOwner = try await makeResumedAbortOwner(
            snapshot: incompleteState.canonicalBytes(),
            binding: incompleteBinding
        ).owner
        let atStep = try await atOwner.preparePreManifestAbort(
            currentUnixSeconds: boundary,
            signing: makeAbortSigningCapability(
                signingKey,
                documentByte: 0xA3,
                eventByte: 0xA4
            )
        )
        #expect(
            try abortReason(in: atStep, binding: incompleteBinding)
                == .missingRequiredParticipant
        )
        let afterOwner = try await makeResumedAbortOwner(
            snapshot: incompleteState.canonicalBytes(),
            binding: incompleteBinding
        ).owner
        let afterStep = try await afterOwner.preparePreManifestAbort(
            currentUnixSeconds: boundary + 1,
            signing: makeAbortSigningCapability(
                signingKey,
                documentByte: 0xA5,
                eventByte: 0xA6
            )
        )
        #expect(
            try abortReason(in: afterStep, binding: incompleteBinding)
                == .missingRequiredParticipant
        )

        let completeBinding = try makeAbortBinding(seed: 0x55)
        let completeState = try makeAbortState(
            binding: completeBinding,
            revision: 31,
            epoch: fixture.epoch,
            phase: .candidateSetAgreement,
            documents: Array(
                fixture.proof.canonicalDocuments.prefix(upTo: admissionStart)
            )
        )
        let completeAtOwner = try await makeResumedAbortOwner(
            snapshot: completeState.canonicalBytes(),
            binding: completeBinding
        ).owner
        let timeoutAtStep = try await completeAtOwner.preparePreManifestAbort(
            currentUnixSeconds: boundary,
            signing: makeAbortSigningCapability(
                signingKey,
                documentByte: 0xA7,
                eventByte: 0xA8
            )
        )
        #expect(
            try abortReason(in: timeoutAtStep, binding: completeBinding)
                == .timeout
        )
        let completeAfterOwner = try await makeResumedAbortOwner(
            snapshot: completeState.canonicalBytes(),
            binding: completeBinding
        ).owner
        let timeoutAfterStep = try await completeAfterOwner
            .preparePreManifestAbort(
                currentUnixSeconds: boundary + 1,
                signing: makeAbortSigningCapability(
                    signingKey,
                    documentByte: 0xA9,
                    eventByte: 0xAA
                )
            )
        #expect(
            try abortReason(in: timeoutAfterStep, binding: completeBinding)
                == .timeout
        )

        let nonceRecord = try fixture.nonceEvent.canonicalRecoveryBytes()
        let nonceIndex = try #require(
            fixture.proof.canonicalDocuments.firstIndex(of: nonceRecord)
        )
        let proposalPendingBinding = try makeAbortBinding(seed: 0x59)
        let proposalPendingState = try makeAbortState(
            binding: proposalPendingBinding,
            revision: 32,
            epoch: fixture.epoch,
            phase: .manifestAgreement,
            documents: Array(
                fixture.proof.canonicalDocuments.prefix(through: nonceIndex)
            )
        )
        let proposalBoundary = try Runtime.preManifestTimeoutBoundary(
            phase: .manifestAgreement,
            discoveryEpochStartUnixSeconds: fixture.epoch
        )
        let controlSigner = fixture.formation.controlCandidate(
            for: fixture.formation.roleElection.roster.controlIdentities[0]
        ).signingKey
        let proposalOwner = try await makeResumedAbortOwner(
            snapshot: proposalPendingState.canonicalBytes(),
            binding: proposalPendingBinding
        ).owner
        let proposalAbort = try await proposalOwner.preparePreManifestAbort(
            currentUnixSeconds: proposalBoundary,
            signing: makeAbortSigningCapability(
                controlSigner,
                documentByte: 0xAB,
                eventByte: 0xAC
            )
        )
        #expect(
            try abortReason(
                in: proposalAbort,
                binding: proposalPendingBinding
            ) == .missingRequiredParticipant
        )

        let expiredOwner = try await makeResumedAbortOwner(
            snapshot: incompleteState.canonicalBytes(),
            binding: incompleteBinding
        ).owner
        let epochEnd = fixture.epoch + Alpha.PrivateDeploymentPolicy.frozen
            .discoveryEpochDurationSeconds
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await expiredOwner.preparePreManifestAbort(
                currentUnixSeconds: epochEnd + 1,
                signing: makeAbortSigningCapability(
                    signingKey,
                    documentByte: 0xAD,
                    eventByte: 0xAE
                )
            )
        }
    }

    @Test("Persist a recognized pre-manifest invalid transition before abort signing")
    func persistPreManifestInvalidAuthenticatedTransition() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeAbortBinding(seed: 0x61)
        let beacon = fixture.beaconEvents[0]
        let signerIdentity = try beacon.decodeCanonicalNostrEvent().publicKey
        let signer = fixture.formation.discovery.candidate(for: signerIdentity)
        let state = try makeAbortState(
            binding: binding,
            revision: 40,
            epoch: fixture.epoch,
            phase: .discovery,
            documents: [
                fixture.opaquePoolDocument,
                fixture.relaySetDocument,
                try beacon.canonicalRecoveryBytes(),
            ]
        )
        let owner = try await makeResumedAbortOwner(
            snapshot: state.canonicalBytes(),
            binding: binding
        ).owner
        let wrongPhase = fixture.acknowledgementEvents[0]
        for rejected in [
            try Runtime.PrivateDeploymentEvent(
                canonicalEventBytes: wrongPhase.canonicalEventBytes,
                acceptedAtUnixSeconds: fixture.epoch + 60
            ),
            try Runtime.PrivateDeploymentEvent(
                canonicalEventBytes: wrongPhase.canonicalEventBytes,
                acceptedAtUnixSeconds: fixture.epoch + 91
            ),
        ] {
            await #expect(throws: Runtime.Failure.invalidStateTransition) {
                _ = try await owner.acceptCandidateSetAcknowledgement(rejected)
            }
            #expect(
                try await owner.nextStep() == .awaitingInput(.discovery)
            )
        }
        let invalidTransition = try await owner
            .acceptCandidateSetAcknowledgement(
                wrongPhase
            )
        let persisted = try await persistAbortStep(
            invalidTransition,
            on: owner
        )
        #expect(
            persisted.next
                == .awaitingPreManifestAbortSignature(.discovery)
        )
        let recovered = try await makeResumedAbortOwner(
            snapshot: persisted.snapshot,
            binding: binding
        )
        #expect(
            recovered.next
                == .awaitingPreManifestAbortSignature(.discovery)
        )
        let signedAbort = try await recovered.owner.preparePreManifestAbort(
            currentUnixSeconds: fixture.epoch + 61,
            signing: makeAbortSigningCapability(
                signer.signingKey,
                documentByte: 0xB1,
                eventByte: 0xB2
            )
        )
        #expect(
            try abortReason(in: signedAbort, binding: binding)
                == .invalidAuthenticatedMessage
        )
    }

    private func makeAbortState(
        binding: Runtime.Binding,
        revision: UInt64,
        epoch: UInt64,
        phase: Runtime.Phase,
        documents: [Data]
    ) throws -> Runtime.RecoveryState {
        let state = Runtime.RecoveryState(
            binding: binding,
            revision: revision,
            discoveryEpochStartUnixSeconds: epoch,
            phase: phase,
            preManifestDocuments: documents,
            preManifestAbortCause: .none,
            manifestState: .forming,
            postManifestJournalState: .uninitialized,
            publicationState: .none,
            terminalState: .active
        )
        try state.validate()
        return state
    }

    private func makeResumedAbortOwner(
        snapshot: Data,
        binding: Runtime.Binding
    ) async throws -> (owner: Runtime.Owner, next: Runtime.Step) {
        let loaded = try Runtime.loadRecovery(
            from: snapshot,
            expectedBinding: binding
        )
        let owner = try Runtime.Owner(claiming: loaded)
        guard case let .recover(.resumePrivateDeployment(continuation)) =
            try await owner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        return (
            owner,
            try await owner.resumePrivateDeployment(continuation)
        )
    }

    private func persistAbortStep(
        _ step: Runtime.Step,
        on owner: Runtime.Owner
    ) async throws -> (snapshot: Data, next: Runtime.Step) {
        guard case let .persist(transition) = step else {
            throw Runtime.Failure.invalidStateTransition
        }
        return (
            transition.replacementSnapshot,
            try await owner.acknowledgePersistence(
                transition,
                exactReadback: transition.replacementSnapshot
            )
        )
    }

    private func persistAndPublishAbort(
        _ step: Runtime.Step,
        on owner: Runtime.Owner
    ) async throws -> Data {
        let persisted = try await persistAbortStep(step, on: owner)
        guard case let .publishPrivateDeployment(publication) = persisted.next
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        let receipt = try await publication.publish(
            using: .init(provisionRoutes: { request in
                request.relayEndpointIdentifiers.enumerated().map {
                    index, endpoint in
                    Runtime.PostManifestProvisionedRoute(
                        relayEndpointIdentifier: endpoint,
                        connection:
                            ScriptedMosaicPrivateAlphaTorConnection(),
                        isolationIdentifier: UUID(
                            uuid: (
                                UInt8(index + 1), 0, 0, 0,
                                0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                            )
                        )
                    )
                }
            })
        )
        let resolution = try await owner
            .acknowledgePrivateDeploymentPublication(consuming: receipt)
        return try await persistAbortStep(resolution, on: owner).snapshot
    }

    private func abortReason(
        in step: Runtime.Step,
        binding: Runtime.Binding
    ) throws -> OpalFusion.Mosaic.Attempt.AbortReason {
        guard case let .persist(transition) = step else {
            throw Runtime.Failure.invalidStateTransition
        }
        let state = try Runtime.RecoveryState.decode(
            from: transition.replacementSnapshot,
            expectedBinding: binding
        )
        guard case let .terminal(.aborted, event, _, _) =
            state.publicationState else {
            throw Runtime.Failure.invalidStateTransition
        }
        let formation = try Runtime.restorePrivateDeploymentFormation(
            discoveryEpochStartUnixSeconds:
                state.discoveryEpochStartUnixSeconds,
            phase: state.phase,
            canonicalDocuments: state.preManifestDocuments
        )
        let nostrEvent = try event.decodeCanonicalNostrEvent()
        let authority = try Runtime.privateDeploymentAbortAuthority(
            formation: formation,
            signerIdentity: nostrEvent.publicKey
        )
        return try Alpha.PreManifestNostrCodec.decodeAbort(
            nostrEvent,
            authority: authority,
            currentUnixSeconds: event.acceptedAtUnixSeconds
        ).reason
    }

    private func makeAbortBinding(seed: UInt8) throws -> Runtime.Binding {
        try .init(
            attemptIdentifier: Data(repeating: seed, count: 32),
            generationIdentifier: Data(repeating: seed &+ 1, count: 32),
            materialIdentifier: Data(repeating: seed &+ 2, count: 32)
        )
    }

    private func makeAbortSigningCapability(
        _ key: OpalCrypto.Secp256k1.SigningKey,
        documentByte: UInt8,
        eventByte: UInt8
    ) throws -> Runtime.PrivateDeploymentSigningCapability {
        .init(
            signingKey: key,
            documentAuxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: documentByte, count: 32)
            ),
            eventAuxiliaryRandomness: try .init(
                rawRepresentation: Data(repeating: eventByte, count: 32)
            )
        )
    }
}
