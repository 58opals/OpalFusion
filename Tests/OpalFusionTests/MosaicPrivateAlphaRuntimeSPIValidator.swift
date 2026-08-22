// MosaicPrivateAlphaRuntimeSPIValidator.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic private-alpha SPI composition", .serialized)
struct MosaicPrivateAlphaRuntimeSPIValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime

    @Test("Complete ten-party live formation within 15 seconds and recover it")
    func completeTenPartyLiveFormationWithinTimingBudget() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeBinding(seed: 0xCF)
        let fresh = try Runtime.createFreshAttempt(
            boundTo: binding,
            discoveryEpochStartUnixSeconds: fixture.epoch
        )
        let owner = try Runtime.Owner(claiming: fresh)
        let clock = ContinuousClock()
        let started = clock.now

        var snapshot = try await persist(await owner.nextStep(), on: owner)
        snapshot = try await persist(
            owner.installPrivateDeploymentContext(
                opaquePoolDocument: fixture.opaquePoolDocument,
                relaySetDocument: fixture.relaySetDocument
            ),
            on: owner
        )
        for event in fixture.beaconEvents {
            snapshot = try await persist(
                owner.acceptAvailabilityBeacon(event),
                on: owner
            )
        }
        snapshot = try await persist(
            owner.completeDiscovery(currentUnixSeconds: fixture.epoch + 60),
            on: owner
        )
        for event in fixture.acknowledgementEvents {
            snapshot = try await persist(
                owner.acceptCandidateSetAcknowledgement(event),
                on: owner
            )
        }
        snapshot = try await persist(
            owner.completeCandidateSetAgreement(),
            on: owner
        )
        for event in fixture.admissionEvents {
            snapshot = try await persist(
                owner.acceptCandidateAdmission(event),
                on: owner
            )
        }
        snapshot = try await persist(
            owner.completeCandidateAdmission(),
            on: owner
        )
        for event in fixture.commitmentEvents {
            snapshot = try await persist(
                owner.acceptRoleCommitment(event),
                on: owner
            )
        }
        snapshot = try await persist(
            owner.completeRoleCommitments(),
            on: owner
        )
        for event in fixture.revealEvents {
            snapshot = try await persist(
                owner.acceptRoleReveal(event),
                on: owner
            )
        }
        snapshot = try await persist(
            owner.completeRoleElection(),
            on: owner
        )
        #expect(
            try await owner.privateDeploymentRole(
                controlIdentity: fixture.proof.conductorControlIdentity
            ) == .conductor
        )
        #expect(
            try await owner.privateDeploymentRole(
                controlIdentity:
                    fixture.proof.contributorControlIdentities[0]
            ) == .contributor
        )
        await #expect(
            throws: Runtime.Failure
                .localControlIdentityNotInPrivateDeployment
        ) {
            _ = try await owner.privateDeploymentRole(
                controlIdentity: Data(repeating: 0xFF, count: 32)
            )
        }
        snapshot = try await persist(
            owner.acceptContributorNonceAllocation(fixture.nonceEvent),
            on: owner
        )
        snapshot = try await persist(
            owner.completeNonceAllocation(),
            on: owner
        )
        snapshot = try await persist(
            owner.acceptManifestProposal(fixture.proposalEvent),
            on: owner
        )
        for event in fixture.signatureEvents {
            snapshot = try await persist(
                owner.acceptManifestSignature(event),
                on: owner
            )
        }
        snapshot = try await persist(
            owner.completeManifestAgreement(),
            on: owner
        )
        let constructionElapsed = started.duration(to: clock.now)
        #expect(constructionElapsed < .seconds(15))

        let loaded = try Runtime.loadRecovery(
            from: snapshot,
            expectedBinding: binding
        )
        let recoveredOwner = try Runtime.Owner(claiming: loaded)
        let recovered = try continuation(from: await recoveredOwner.nextStep())
        _ = try await recoveredOwner.resumePrivateDeployment(recovered)
        let proof = try await recoveredOwner
            .makeTransportBootstrapPrivateDeploymentProof()

        #expect(proof.roundIdentifier == fixture.proof.roundIdentifier)
    }

    @Test("Expose the signed post-manifest phase start to timing capabilities")
    func exposeSignedPostManifestPhaseStart() throws {
        let deadlines = try Alpha.DeadlineSchedule(
            phaseStart: 1_800_000_000,
            walletReservation: 1_800_000_060,
            groupedCommitment: 1_800_000_120,
            anonymousComponentSubmission: 1_800_000_240,
            transcriptAgreement: 1_800_000_300,
            bchSigning: 1_800_000_360
        )
        let request = try Runtime.PostManifestConstruction
            .makeTimestampRequest(
                recipientEventIdentity: Data(repeating: 0x51, count: 32),
                phase: .anonymousComponentSubmission,
                sequence: 7,
                expiryUnixSeconds: deadlines.anonymousComponentSubmission,
                deadlines: deadlines
            )

        #expect(request.phaseStartUnixSeconds == deadlines.phaseStart)
        #expect(request.phase == .anonymousComponentSubmission)
        #expect(request.sequence == 7)
        #expect(
            request.expiryUnixSeconds
                == deadlines.anonymousComponentSubmission
        )
    }

    @Test("Restore signed formation prefixes and construct the existing runtime")
    func restoreSignedFormationPrefixesAndConstructRuntime() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeBinding(seed: 0xD0)
        let fresh = try Runtime.createFreshAttempt(
            boundTo: binding,
            discoveryEpochStartUnixSeconds: fixture.epoch
        )
        var owner = try Runtime.Owner(claiming: fresh)
        var snapshot = try await persist(await owner.nextStep(), on: owner)
        snapshot = try await persist(
            owner.installPrivateDeploymentContext(
                opaquePoolDocument: fixture.opaquePoolDocument,
                relaySetDocument: fixture.relaySetDocument
            ),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .discovery
        )
        for event in fixture.beaconEvents {
            snapshot = try await persist(
                owner.acceptAvailabilityBeacon(event),
                on: owner
            )
            owner = try await reloadFormation(
                snapshot,
                binding: binding,
                phase: .discovery
            )
        }
        snapshot = try await persist(
            owner.completeDiscovery(currentUnixSeconds: fixture.epoch + 60),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .candidateSetAgreement
        )
        let localInputs = try MosaicPrivateDeploymentFixtures
            .makeLocalFormationInputs(formation: fixture.formation)
        let localAcknowledgement = try await persistAndPublish(
            owner.prepareCandidateSetAcknowledgement(
                createdAtUnixSeconds: fixture.epoch + 61,
                signing: makeSigningCapability(
                    localInputs.discoveryCandidate.signingKey,
                    documentByte: 0xB1,
                    eventByte: 0x30
                )
            ),
            on: owner
        )
        snapshot = localAcknowledgement.snapshot
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .candidateSetAgreement
        )
        #expect(
            try await owner.acceptCandidateSetAcknowledgement(
                duplicate(localAcknowledgement.event, acceptedAtOffset: 7)
            ) == .ignoredDuplicate(.candidateSetAgreement)
        )
        for event in try eventsExcludingSigner(
            localAcknowledgement.event,
            from: fixture.acknowledgementEvents
        ) {
            snapshot = try await persist(
                owner.acceptCandidateSetAcknowledgement(event),
                on: owner
            )
            owner = try await reloadFormation(
                snapshot,
                binding: binding,
                phase: .candidateSetAgreement
            )
        }
        snapshot = try await persist(
            owner.completeCandidateSetAgreement(),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .admission
        )
        let localAdmission = try await persistAndPublish(
            owner.prepareCandidateAdmission(
                createdAtUnixSeconds: fixture.epoch + 91,
                discoverySigning: makeSigningCapability(
                    localInputs.discoveryCandidate.signingKey,
                    documentByte: 0xB2,
                    eventByte: 0x40
                ),
                controlSigning: makeSigningCapability(
                    localInputs.admissionControlCandidate.signingKey,
                    documentByte: 0xB3,
                    eventByte: 0x41
                )
            ),
            on: owner
        )
        snapshot = localAdmission.snapshot
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .admission
        )
        #expect(
            try await owner.acceptCandidateAdmission(
                duplicate(localAdmission.event, acceptedAtOffset: 7)
            ) == .ignoredDuplicate(.admission)
        )
        for event in try eventsExcludingSigner(
            localAdmission.event,
            from: fixture.admissionEvents
        ) {
            snapshot = try await persist(
                owner.acceptCandidateAdmission(event),
                on: owner
            )
            owner = try await reloadFormation(
                snapshot,
                binding: binding,
                phase: .admission
            )
        }
        snapshot = try await persist(
            owner.completeCandidateAdmission(),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .controlRosterAgreement
        )
        let localCommitment = try await persistAndPublish(
            owner.prepareRoleCommitment(
                randomness: localInputs.roleRandomness,
                createdAtUnixSeconds: fixture.epoch + 121,
                signing: makeSigningCapability(
                    localInputs.roleCandidate.signingKey,
                    documentByte: 0x01,
                    eventByte: 0x50
                )
            ),
            on: owner
        )
        snapshot = localCommitment.snapshot
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .controlRosterAgreement
        )
        #expect(
            try await owner.acceptRoleCommitment(
                duplicate(localCommitment.event, acceptedAtOffset: 7)
            ) == .ignoredDuplicate(.controlRosterAgreement)
        )
        for event in try eventsExcludingSigner(
            localCommitment.event,
            from: fixture.commitmentEvents
        ) {
            snapshot = try await persist(
                owner.acceptRoleCommitment(event),
                on: owner
            )
            owner = try await reloadFormation(
                snapshot,
                binding: binding,
                phase: .controlRosterAgreement
            )
        }
        snapshot = try await persist(
            owner.completeRoleCommitments(),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .roleElection
        )
        let localReveal = try await persistAndPublish(
            owner.prepareRoleReveal(
                randomness: localInputs.roleRandomness,
                createdAtUnixSeconds: fixture.epoch + 151,
                signing: makeSigningCapability(
                    localInputs.roleCandidate.signingKey,
                    documentByte: 0x02,
                    eventByte: 0x60
                )
            ),
            on: owner
        )
        snapshot = localReveal.snapshot
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .roleElection
        )
        #expect(
            try await owner.acceptRoleReveal(
                duplicate(localReveal.event, acceptedAtOffset: 7)
            ) == .ignoredDuplicate(.roleElection)
        )
        for event in try eventsExcludingSigner(
            localReveal.event,
            from: fixture.revealEvents
        ) {
            snapshot = try await persist(
                owner.acceptRoleReveal(event),
                on: owner
            )
            owner = try await reloadFormation(
                snapshot,
                binding: binding,
                phase: .roleElection
            )
        }
        snapshot = try await persist(owner.completeRoleElection(), on: owner)
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .nonceAllocation
        )
        let localNonce = try await persistAndPublish(
            owner.prepareContributorNonceAllocation(
                publicSources: localInputs.publicSources,
                createdAtUnixSeconds: fixture.epoch + 181,
                signing: makeSigningCapability(
                    localInputs.conductorCandidate.signingKey,
                    documentByte: 0x03,
                    eventByte: 0x70
                )
            ),
            on: owner
        )
        snapshot = localNonce.snapshot
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .nonceAllocation
        )
        #expect(
            try await owner.acceptContributorNonceAllocation(
                duplicate(localNonce.event, acceptedAtOffset: 7)
            ) == .ignoredDuplicate(.nonceAllocation)
        )
        snapshot = try await persist(owner.completeNonceAllocation(), on: owner)
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .manifestAgreement
        )
        let localProposal = try await persistAndPublish(
            owner.prepareManifestProposal(
                authorizationKeys: localInputs.authorizationKeys,
                createdAtUnixSeconds: fixture.epoch + 182,
                signing: makeSigningCapability(
                    localInputs.conductorCandidate.signingKey,
                    documentByte: 0x04,
                    eventByte: 0x71
                )
            ),
            on: owner
        )
        snapshot = localProposal.snapshot
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .manifestAgreement
        )
        #expect(
            try await owner.acceptManifestProposal(
                duplicate(localProposal.event, acceptedAtOffset: 7)
            ) == .ignoredDuplicate(.manifestAgreement)
        )
        let localSignature = try await persistAndPublish(
            owner.prepareManifestSignature(
                createdAtUnixSeconds: fixture.epoch + 183,
                signing: makeSigningCapability(
                    localInputs.manifestSigner.signingKey,
                    documentByte: 0xC0,
                    eventByte: 0x80
                )
            ),
            on: owner
        )
        snapshot = localSignature.snapshot
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .manifestAgreement
        )
        #expect(
            try await owner.acceptManifestSignature(
                duplicate(localSignature.event, acceptedAtOffset: 7)
            ) == .ignoredDuplicate(.manifestAgreement)
        )
        for event in try eventsExcludingSigner(
            localSignature.event,
            from: fixture.signatureEvents
        ) {
            snapshot = try await persist(
                owner.acceptManifestSignature(event),
                on: owner
            )
            owner = try await reloadFormation(
                snapshot,
                binding: binding,
                phase: .manifestAgreement
            )
        }
        let sealedSnapshot = try await persist(
            owner.completeManifestAgreement(),
            on: owner
        )
        let freshTransportProof = try await owner
            .makeTransportBootstrapPrivateDeploymentProof()
        #expect(
            freshTransportProof.roundIdentifier
                == fixture.proof.roundIdentifier
        )
        #expect(
            freshTransportProof.relayEndpointIdentifiers
                == fixture.proof.relayEndpointIdentifiers
        )

        let sealedRecovery = try Runtime.loadRecovery(
            from: sealedSnapshot,
            expectedBinding: binding
        )
        let sealedOwner = try Runtime.Owner(claiming: sealedRecovery)
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await sealedOwner
                .makeTransportBootstrapPrivateDeploymentProof()
        }
        let sealedContinuation = try continuation(
            from: await sealedOwner.nextStep()
        )
        _ = try await sealedOwner.resumePrivateDeployment(
            sealedContinuation
        )
        let recoveredTransportProof = try await sealedOwner
            .makeTransportBootstrapPrivateDeploymentProof()
        #expect(recoveredTransportProof == freshTransportProof)
        let admissionStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let publicationStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminalStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let routeStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let capabilities = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: fixture.localControlIdentity,
                admissionStore: admissionStore,
                publicationStore: publicationStore,
                terminalStore: terminalStore,
                routeStore: routeStore
            )
        _ = try await persist(
            sealedOwner.preparePostManifestRuntime(
                localControlIdentity: fixture.localControlIdentity,
                capabilities: capabilities
            ),
            on: sealedOwner
        )
        await #expect(throws: Runtime.Failure
            .localControlIdentityNotInPrivateDeployment) {
            _ = try await sealedOwner.makePostManifestConstruction(
                localControlIdentity: Data(repeating: 0xFF, count: 32)
            )
        }
        let construction = try await sealedOwner.makePostManifestConstruction(
            localControlIdentity: fixture.localControlIdentity
        )
        let constructionBinding = construction.binding
        let constructionIdentity = construction.localControlIdentity
        let constructionIsConductor = construction.isConductor
        #expect(constructionBinding == binding)
        #expect(constructionIdentity == fixture.localControlIdentity)
        #expect(constructionIsConductor)
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await sealedOwner.makePostManifestConstruction(
                localControlIdentity: fixture.localControlIdentity
            )
        }
        #expect(routeStore.recordedProvisionCallCount == 0)
        #expect(throws: Runtime.Failure.recoveryBindingMismatch) {
            _ = try Runtime.loadRecovery(
                from: sealedSnapshot,
                expectedBinding: makeBinding(seed: 0xE0)
            )
        }
    }

    @Test("Reject an event from the wrong formation phase")
    func rejectEventFromWrongFormationPhase() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let fresh = try Runtime.createFreshAttempt(
            boundTo: makeBinding(seed: 0xF0),
            discoveryEpochStartUnixSeconds: fixture.epoch
        )
        let owner = try Runtime.Owner(claiming: fresh)
        _ = try await persist(await owner.nextStep(), on: owner)
        _ = try await persist(
            owner.installPrivateDeploymentContext(
                opaquePoolDocument: fixture.opaquePoolDocument,
                relaySetDocument: fixture.relaySetDocument
            ),
            on: owner
        )
        await #expect(throws: (any Error).self) {
            _ = try await owner.acceptAvailabilityBeacon(
                fixture.acknowledgementEvents[0]
            )
        }
        #expect(try await owner.nextStep() == .awaitingInput(.discovery))
    }

    @Test("Construct persist recover and publish one exact local formation event")
    func constructPersistRecoverAndPublishLocalFormationEvent() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeBinding(seed: 0xA0)
        let fresh = try Runtime.createFreshAttempt(
            boundTo: binding,
            discoveryEpochStartUnixSeconds: fixture.epoch
        )
        let owner = try Runtime.Owner(claiming: fresh)
        _ = try await persist(await owner.nextStep(), on: owner)
        _ = try await persist(
            owner.installPrivateDeploymentContext(
                opaquePoolDocument: fixture.opaquePoolDocument,
                relaySetDocument: fixture.relaySetDocument
            ),
            on: owner
        )
        let localBeacon = MosaicPrivateDeploymentFixtures
            .makeLocalBeaconInput(
                formation: fixture.formation
            )
        let pending = try await owner.prepareAvailabilityBeacon(
            proofOfWorkNonce: localBeacon.proofOfWorkNonce,
            createdAtUnixSeconds: fixture.epoch + 1,
            signing: makeSigningCapability(
                localBeacon.candidate.signingKey,
                documentByte: 0x91,
                eventByte: 0x92
            )
        )
        guard case let .persist(transition) = pending else {
            throw Runtime.Failure.invalidStateTransition
        }
        let next = try await owner.acknowledgePersistence(
            transition,
            exactReadback: transition.replacementSnapshot
        )
        guard case let .publishPrivateDeployment(firstPublication) = next else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(
            try await owner.acceptAvailabilityBeacon(try .init(
                canonicalEventBytes: firstPublication.canonicalEventBytes,
                acceptedAtUnixSeconds: fixture.epoch + 2
            )) == .ignoredDuplicate(.discovery)
        )
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await owner.nextStep()
        }

        let loaded = try Runtime.loadRecovery(
            from: transition.replacementSnapshot,
            expectedBinding: binding
        )
        let recoveredOwner = try Runtime.Owner(claiming: loaded)
        guard case let .recover(.publishPrivateDeployment(publication)) =
            try await recoveredOwner.nextStep() else {
            throw Runtime.Failure.invalidStateTransition
        }
        #expect(publication == firstPublication)
        let publicationCopy = publication
        let publishedBytes = publication.canonicalEventBytes
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await recoveredOwner.nextStep()
        }
        let provisionStore = MosaicPrivateAlphaRuntimePersistenceStore()
        let relayCapabilities = Runtime.PrivateDeploymentRelayCapabilities(
            provisionRoutes: { request in
                provisionStore.recordProvisionCall()
                return request.relayEndpointIdentifiers.enumerated().map {
                    index,
                    endpoint in
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
            }
        )
        let receipt = try await publication.publish(using: relayCapabilities)
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await publicationCopy.publish(using: relayCapabilities)
        }
        #expect(provisionStore.recordedProvisionCallCount == 1)
        let resolution = try await recoveredOwner
            .acknowledgePrivateDeploymentPublication(consuming: receipt)
        _ = try await persist(resolution, on: recoveredOwner)

        #expect(
            try await recoveredOwner.acceptAvailabilityBeacon(try .init(
                canonicalEventBytes: publishedBytes,
                acceptedAtUnixSeconds: fixture.epoch + 2
            )) == .ignoredDuplicate(.discovery)
        )
    }

    @Test("Validate runtime capabilities before CAS and recover journal crash cuts")
    func validateCapabilitiesAndRecoverJournalPreparation() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeBinding(seed: 0x91)
        let sealedSnapshot = try makeSealedSnapshot(
            proof: fixture.proof,
            binding: binding,
            epoch: fixture.epoch
        )
        let templateAdmission = MosaicPrivateAlphaRuntimePersistenceStore()
        let templatePublication = MosaicPrivateAlphaRuntimePersistenceStore()
        let templateTerminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let templateRoutes = MosaicPrivateAlphaRuntimePersistenceStore()
        let template = try MosaicPrivateDeploymentFixtures
            .makeRuntimeCapabilities(
                formation: fixture.formation,
                localControlIdentity: fixture.localControlIdentity,
                admissionStore: templateAdmission,
                publicationStore: templatePublication,
                terminalStore: templateTerminal,
                routeStore: templateRoutes
            )

        func makeStoresAndCapabilities() throws -> (
            MosaicPrivateAlphaRuntimePersistenceStore,
            MosaicPrivateAlphaRuntimePersistenceStore,
            MosaicPrivateAlphaRuntimePersistenceStore,
            MosaicPrivateAlphaRuntimePersistenceStore,
            Runtime.PostManifestRuntimeCapabilities
        ) {
            let admission = MosaicPrivateAlphaRuntimePersistenceStore()
            let publication = MosaicPrivateAlphaRuntimePersistenceStore()
            let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
            let routes = MosaicPrivateAlphaRuntimePersistenceStore()
            let relays = Runtime.PostManifestRelayCapabilities(
                provisionRoutes: { _ in
                    routes.recordProvisionCall()
                    throw Runtime.Failure.invalidStateTransition
                },
                makeSubscriptionIdentifier:
                    template.relays.makeSubscriptionIdentifier,
                awaitAnonymousPublicationPermit:
                    template.relays.awaitAnonymousPublicationPermit,
                maximumSubscriptionIdentifierByteCount:
                    template.relays.maximumSubscriptionIdentifierByteCount,
                maximumPendingEventCount:
                    template.relays.maximumPendingEventCount,
                maximumPendingRelayOutputCount:
                    template.relays.maximumPendingRelayOutputCount
            )
            return (
                admission,
                publication,
                terminal,
                routes,
                Runtime.PostManifestRuntimeCapabilities(
                    mailboxes: template.mailboxes,
                    relays: relays,
                    timing: template.timing,
                    admissionPersistence: .init(
                        load: admission.load,
                        compareAndSwap: admission.compareAndSwap
                    ),
                    publicationPersistence: .init(
                        load: publication.load,
                        compareAndSwap: publication.compareAndSwap
                    ),
                    terminalPersistence: .init(
                        load: terminal.load,
                        compareAndSwap: terminal.compareAndSwap
                    ),
                    maximumPendingInputCount:
                        template.maximumPendingInputCount
                )
            )
        }

        do {
            let (admission, publication, _, routes, capabilities) =
                try makeStoresAndCapabilities()
            let wrongMailboxes = Runtime.PostManifestMailboxCapabilities(
                controlMailboxes: Array(
                    capabilities.mailboxes.controlMailboxes.dropLast()
                ),
                localControlRecipientSigningKey: capabilities.mailboxes
                    .localControlRecipientSigningKey,
                anonymous: capabilities.mailboxes.anonymous
            )
            let owner = try await resumedOwner(
                snapshot: sealedSnapshot,
                binding: binding
            )
            await #expect(throws: Runtime.Failure.invalidStateTransition) {
                _ = try await owner.preparePostManifestRuntime(
                    localControlIdentity: fixture.localControlIdentity,
                    capabilities: replacingMailboxes(
                        capabilities,
                        with: wrongMailboxes
                    )
                )
            }
            #expect(admission.recordedCompareAndSwapCallCount == 0)
            #expect(publication.recordedCompareAndSwapCallCount == 0)
            #expect(routes.recordedProvisionCallCount == 0)
        }

        do {
            let (admission, publication, _, routes, capabilities) =
                try makeStoresAndCapabilities()
            let wrongKey = try MosaicPrivateDeploymentFixtures
                .CandidateKeyMaterial(scalar: 0xFA).signingKey
            let wrongMailboxes = Runtime.PostManifestMailboxCapabilities(
                controlMailboxes: capabilities.mailboxes.controlMailboxes,
                localControlRecipientSigningKey: wrongKey,
                anonymous: capabilities.mailboxes.anonymous
            )
            let owner = try await resumedOwner(
                snapshot: sealedSnapshot,
                binding: binding
            )
            await #expect(throws: (any Error).self) {
                _ = try await owner.preparePostManifestRuntime(
                    localControlIdentity: fixture.localControlIdentity,
                    capabilities: replacingMailboxes(
                        capabilities,
                        with: wrongMailboxes
                    )
                )
            }
            #expect(admission.recordedCompareAndSwapCallCount == 0)
            #expect(publication.recordedCompareAndSwapCallCount == 0)
            #expect(routes.recordedProvisionCallCount == 0)
        }

        do {
            let (admission, publication, _, routes, capabilities) =
                try makeStoresAndCapabilities()
            let wrongMailboxes = Runtime.PostManifestMailboxCapabilities(
                controlMailboxes: capabilities.mailboxes.controlMailboxes,
                localControlRecipientSigningKey: capabilities.mailboxes
                    .localControlRecipientSigningKey,
                anonymous: .contributor([])
            )
            let owner = try await resumedOwner(
                snapshot: sealedSnapshot,
                binding: binding
            )
            await #expect(throws: Runtime.Failure.invalidStateTransition) {
                _ = try await owner.preparePostManifestRuntime(
                    localControlIdentity: fixture.localControlIdentity,
                    capabilities: replacingMailboxes(
                        capabilities,
                        with: wrongMailboxes
                    )
                )
            }
            #expect(admission.recordedCompareAndSwapCallCount == 0)
            #expect(publication.recordedCompareAndSwapCallCount == 0)
            #expect(routes.recordedProvisionCallCount == 0)
        }

        do {
            let (admission, publication, _, routes, capabilities) =
                try makeStoresAndCapabilities()
            let unboundedRelays = Runtime.PostManifestRelayCapabilities(
                provisionRoutes: capabilities.relays.provisionRoutes,
                makeSubscriptionIdentifier:
                    capabilities.relays.makeSubscriptionIdentifier,
                maximumSubscriptionIdentifierByteCount: Int.max
            )
            let unbounded = Runtime.PostManifestRuntimeCapabilities(
                mailboxes: capabilities.mailboxes,
                relays: unboundedRelays,
                timing: capabilities.timing,
                admissionPersistence: capabilities.admissionPersistence,
                publicationPersistence: capabilities.publicationPersistence,
                terminalPersistence: capabilities.terminalPersistence,
                maximumPendingInputCount: Int.max
            )
            let owner = try await resumedOwner(
                snapshot: sealedSnapshot,
                binding: binding
            )
            await #expect(throws: Runtime.Failure.invalidStateTransition) {
                _ = try await owner.preparePostManifestRuntime(
                    localControlIdentity: fixture.localControlIdentity,
                    capabilities: unbounded
                )
            }
            #expect(admission.recordedCompareAndSwapCallCount == 0)
            #expect(publication.recordedCompareAndSwapCallCount == 0)
            #expect(routes.recordedProvisionCallCount == 0)
        }

        let (admission, publication, _, routes, capabilities) =
            try makeStoresAndCapabilities()
        admission.failNextCompareAndSwap()
        let firstOwner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        await #expect(throws: Runtime.Failure.exactReadbackMismatch) {
            _ = try await firstOwner.preparePostManifestRuntime(
                localControlIdentity: fixture.localControlIdentity,
                capabilities: capabilities
            )
        }
        #expect(publication.recordedCompareAndSwapCallCount == 1)
        #expect(admission.recordedCompareAndSwapCallCount == 1)
        #expect(routes.recordedProvisionCallCount == 0)

        let secondOwner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        _ = try await secondOwner.preparePostManifestRuntime(
            localControlIdentity: fixture.localControlIdentity,
            capabilities: capabilities
        )
        #expect(publication.recordedCompareAndSwapCallCount == 1)
        #expect(admission.recordedCompareAndSwapCallCount == 2)

        let thirdOwner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        let initializedSnapshot = try await persist(
            thirdOwner.preparePostManifestRuntime(
                localControlIdentity: fixture.localControlIdentity,
                capabilities: capabilities
            ),
            on: thirdOwner
        )
        #expect(publication.recordedCompareAndSwapCallCount == 1)
        #expect(admission.recordedCompareAndSwapCallCount == 2)
        #expect(routes.recordedProvisionCallCount == 0)

        publication.remove(binding)
        let missingPublicationOwner = try await resumedOwner(
            snapshot: initializedSnapshot,
            binding: binding
        )
        let missingPublicationConstruction = try await
            missingPublicationOwner.makePostManifestConstruction(
                localControlIdentity: fixture.localControlIdentity
            )
        #expect(throws: (any Error).self) {
            let selection = try missingPublicationConstruction
                .makeRelaySelection(capabilities.relays)
            _ = try missingPublicationConstruction.makePublicationJournal(
                relaySelection: selection,
                persistence: capabilities.publicationPersistence
            )
        }
        #expect(routes.recordedProvisionCallCount == 0)

        let (_, replacementPublication, _, replacementRoutes,
             replacementCapabilities) = try makeStoresAndCapabilities()
        let reprepareOwner = try await resumedOwner(
            snapshot: sealedSnapshot,
            binding: binding
        )
        let reinitializedSnapshot = try await persist(
            reprepareOwner.preparePostManifestRuntime(
                localControlIdentity: fixture.localControlIdentity,
                capabilities: replacementCapabilities
            ),
            on: reprepareOwner
        )
        let missingAdmissionOwner = try await resumedOwner(
            snapshot: reinitializedSnapshot,
            binding: binding
        )
        let missingAdmissionConstruction = try await missingAdmissionOwner
            .makePostManifestConstruction(
                localControlIdentity: fixture.localControlIdentity
            )
        let missingAdmissionStore = MosaicPrivateAlphaRuntimePersistenceStore()
        #expect(throws: (any Error).self) {
            try Alpha.PostManifestAdmissionJournal
                .initializeRecoverySnapshot(
                    binding: binding,
                    persistence: .init(
                        load: missingAdmissionStore.load,
                        compareAndSwap:
                            missingAdmissionStore.compareAndSwap
                    ),
                    context: missingAdmissionConstruction
                        .makeAdmissionContext(replacementCapabilities),
                    requireExisting: true
                )
        }
        #expect(replacementPublication.recordedCompareAndSwapCallCount == 1)
        #expect(replacementRoutes.recordedProvisionCallCount == 0)
    }

    @Test("Canonicalize alternate signed discovery beacon independent of arrival")
    func canonicalizeAlternateDiscoveryBeacon() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let original = fixture.beaconEvents[0]
        let alternate = try MosaicPrivateDeploymentFixtures
            .makeAlternateBeaconEvent(
                formation: fixture.formation,
                documentAuxiliaryByte: 0xD1,
                eventAuxiliaryByte: 0xD2
            )

        func result(
            binding: Runtime.Binding,
            events: [Runtime.PrivateDeploymentEvent]
        ) async throws -> Data {
            let fresh = try Runtime.createFreshAttempt(
                boundTo: binding,
                discoveryEpochStartUnixSeconds: fixture.epoch
            )
            let owner = try Runtime.Owner(claiming: fresh)
            var snapshot = try await persist(await owner.nextStep(), on: owner)
            snapshot = try await persist(
                owner.installPrivateDeploymentContext(
                    opaquePoolDocument: fixture.opaquePoolDocument,
                    relaySetDocument: fixture.relaySetDocument
                ),
                on: owner
            )
            for event in events {
                switch try await owner.acceptAvailabilityBeacon(event) {
                case let .persist(transition):
                    _ = try await owner.acknowledgePersistence(
                        transition,
                        exactReadback: transition.replacementSnapshot
                    )
                    snapshot = transition.replacementSnapshot
                case .ignoredDuplicate(.discovery):
                    break
                default:
                    throw Runtime.Failure.invalidStateTransition
                }
            }
            let records = try Runtime.RecoveryState.decode(
                from: snapshot,
                expectedBinding: binding
            ).preManifestDocuments
            guard let last = records.last else {
                throw Runtime.Failure.invalidStateTransition
            }
            return last
        }

        let forward = try await result(
            binding: makeBinding(seed: 0x84),
            events: [original, alternate]
        )
        let reverse = try await result(
            binding: makeBinding(seed: 0x87),
            events: [alternate, original]
        )
        #expect(forward == reverse)
    }

    @Test("Authenticate every recovered admission before provisioning routes")
    func authenticateRecoveredAdmissionsBeforeRoutes() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let roster = fixture.formation.roleElection.roster
        let contributorIdentity = Data(
            try #require(roster.contributors.first).validatedBytes
        )
        let contributor = fixture.formation.controlCandidate(
            for: .init(validatedBytes: Array(contributorIdentity))
        )
        let contributorEventKey = try MosaicPrivateDeploymentFixtures
            .CandidateKeyMaterial(scalar: 0xE1)
            .signingKey

        for scenario in 0 ... 5 {
            let binding = try makeBinding(seed: UInt8(0xA8 + scenario * 3))
            let admission = MosaicPrivateAlphaRuntimePersistenceStore()
            let publication = MosaicPrivateAlphaRuntimePersistenceStore()
            let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
            let routes = MosaicPrivateAlphaRuntimePersistenceStore()
            let capabilities = try MosaicPrivateDeploymentFixtures
                .makeRuntimeCapabilities(
                    formation: fixture.formation,
                    localControlIdentity: contributorIdentity,
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
                    localControlIdentity: contributorIdentity,
                    capabilities: capabilities
                ),
                on: owner
            )
            let construction = try await owner.makePostManifestConstruction(
                localControlIdentity: contributorIdentity
            )
            let context = construction.makeAdmissionContext(capabilities)
            let acceptedAt = construction.completeManifest.core.deadlines
                .phaseStart + 1
            let validRecord = try MosaicPrivateDeploymentFixtures
                .makePostManifestControlRecoveryRecord(
                    formation: fixture.formation,
                    bootstrap: construction.bootstrap,
                    recipientSigningKey: capabilities.mailboxes
                        .localControlRecipientSigningKey,
                    acceptedAtUnixSeconds: acceptedAt
                )
            let store = Alpha.PostManifestAdmissionJournal.recoveryStore(
                binding: binding,
                persistence: capabilities.admissionPersistence
            )
            switch scenario {
            case 0:
                try store.append(
                    context,
                    0,
                    .control(
                        sender: roster.conductor,
                        sequence: 0,
                        messageDigest: [UInt8](repeating: 0x31, count: 32),
                        source: .init(
                            canonicalGiftWrapBytes: Data([0x00]),
                            acceptedAtUnixSeconds: acceptedAt
                        )
                    )
                )
            case 1:
                let unknownKey = try MosaicPrivateDeploymentFixtures
                    .CandidateKeyMaterial(scalar: 0xF2).signingKey
                try store.append(
                    context,
                    0,
                    try MosaicPrivateDeploymentFixtures
                        .makePostManifestControlRecoveryRecord(
                            formation: fixture.formation,
                            bootstrap: construction.bootstrap,
                            recipientSigningKey: unknownKey,
                            acceptedAtUnixSeconds: acceptedAt
                        )
                )
            case 2:
                guard case let .control(
                    sender,
                    sequence,
                    _,
                    source
                ) = validRecord else {
                    throw Runtime.Failure.invalidStateTransition
                }
                try store.append(
                    context,
                    0,
                    .control(
                        sender: sender,
                        sequence: sequence,
                        messageDigest: [UInt8](repeating: 0x32, count: 32),
                        source: source
                    )
                )
            case 3:
                try store.append(context, 0, validRecord)
                #expect(throws: (any Error).self) {
                    try store.append(context, 1, validRecord)
                }
            case 4:
                guard case let .control(
                    sender,
                    sequence,
                    _,
                    source
                ) = validRecord else {
                    throw Runtime.Failure.invalidStateTransition
                }
                try store.append(context, 0, validRecord)
                #expect(throws: (any Error).self) {
                    try store.append(
                        context,
                        1,
                        .control(
                            sender: sender,
                            sequence: sequence,
                            messageDigest: [UInt8](
                                repeating: 0x33,
                                count: 32
                            ),
                            source: source
                        )
                    )
                }
            default:
                try store.append(context, 0, validRecord)
            }
            let host = Runtime.PostManifestContributorHost(
                transactionHost:
                    MosaicPrivateAlphaRejectingCompleteTransactionHost(),
                previousOutputSource:
                    MosaicPrivateAlphaRejectingPreviousOutputSource(),
                controlSigningKey: contributor.signingKey,
                controlEventSigningKey: contributorEventKey,
                loadSlotSecrets: { _, _ in
                    throw Runtime.Failure.invalidStateTransition
                }
            )
            var constructionFailed = false
            do {
                _ = try await construction.makeContributorExecution(
                    host: host,
                    capabilities: capabilities
                )
            } catch {
                constructionFailed = true
            }
            #expect(constructionFailed)
            #expect(
                routes.recordedProvisionCallCount == (scenario == 5 ? 1 : 0)
            )
        }
    }

    @Test("Bound subscription identifier bytes and JSON frame expansion")
    func boundSubscriptionIdentifierBytesAndJSONFrameExpansion() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let contributor = try #require(
            fixture.formation.roleElection.roster.contributors.first
        )
        let localIdentity = Data(contributor.validatedBytes)
        let binding = try makeBinding(seed: 0xE7)
        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routes = MosaicPrivateAlphaRuntimePersistenceStore()
        let baseCapabilities = try MosaicPrivateDeploymentFixtures
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
                capabilities: baseCapabilities
            ),
            on: owner
        )
        let construction = try await owner.makePostManifestConstruction(
            localControlIdentity: localIdentity
        )

        func makeRelays(
            identifier: @escaping @Sendable (
                Runtime.PostManifestRouteRequest,
                String
            ) throws -> String
        ) -> Runtime.PostManifestRelayCapabilities {
            .init(
                provisionRoutes: { requests in
                    routes.recordProvisionCall()
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
                makeSubscriptionIdentifier: identifier,
                maximumSubscriptionIdentifierByteCount: 64
            )
        }

        let escapedRelays = makeRelays { request, endpoint in
            guard let index = request.relayEndpointIdentifiers
                    .firstIndex(of: endpoint) else {
                throw Runtime.Failure.invalidStateTransition
            }
            return String(repeating: "\"", count: 63) + String(index)
        }
        let escapedCapabilities = replacingRelays(
            baseCapabilities,
            with: escapedRelays
        )
        let relaySelection = try construction.makeRelaySelection(
            escapedRelays
        )
        let transportOwner = try construction.makeTransportOwner(
            capabilities: escapedCapabilities,
            relaySelection: relaySelection
        )
        let inbound = try await transportOwner.provisionInboundRuntime()
        let codingLimits = try construction.makeCodingLimits(escapedRelays)
        try Alpha.PostManifestRelayFanIn.validateRoutePlan(
            role: .contributor,
            maximumAnonymousRecipientCount: 0,
            manifestRelaySetDigest:
                construction.completeManifest.core.relaySetDigest,
            recipientRouteGroups: inbound.recipientRouteGroups,
            relaySelection: inbound.relaySelection,
            codingLimits: codingLimits,
            maximumPendingEventCount:
                escapedRelays.maximumPendingEventCount
        )
        for identifier in inbound.recipientRouteGroups.flatMap({
            $0.subscriptionIdentifiers.values
        }) {
            #expect(identifier.value.utf8.count == 64)
            #expect(try JSONEncoder().encode(identifier.value).count > 64)
        }
        for route in inbound.recipientRouteGroups.flatMap(\.routes) {
            await route.connection.close()
        }

        let overlongRelays = makeRelays { _, _ in
            String(repeating: "é", count: 33)
        }
        let overlongOwner = try construction.makeTransportOwner(
            capabilities: replacingRelays(
                baseCapabilities,
                with: overlongRelays
            ),
            relaySelection: relaySelection
        )
        await #expect(
            throws: Alpha.PostManifestAttemptTransportOwner.Failure
                .subscriptionIdentifierUnavailable
        ) {
            _ = try await overlongOwner.provisionInboundRuntime()
        }
        #expect(routes.recordedProvisionCallCount == 2)
    }

    @Test("Persist and reload received nonce and manifest proposal singletons")
    func persistReceivedFormationSingletons() async throws {
        let fixture = try MosaicPrivateDeploymentFixtures
            .makePrivateAlphaRuntimeProof()
        let binding = try makeBinding(seed: 0x8A)
        let nonceRecord = try fixture.nonceEvent.canonicalRecoveryBytes()
        let nonceIndex = try #require(
            fixture.proof.canonicalDocuments.firstIndex(of: nonceRecord)
        )
        let state = Runtime.RecoveryState(
            binding: binding,
            revision: 30,
            discoveryEpochStartUnixSeconds: fixture.epoch,
            phase: .nonceAllocation,
            preManifestDocuments: Array(
                fixture.proof.canonicalDocuments.prefix(upTo: nonceIndex)
            ),
            preManifestAbortCause: .none,
            manifestState: .forming,
            postManifestJournalState: .uninitialized,
            publicationState: .none,
            terminalState: .active
        )
        try state.validate()
        var snapshot = try state.canonicalBytes()
        var owner = try await resumedOwner(
            snapshot: snapshot,
            binding: binding
        )
        snapshot = try await persist(
            owner.acceptContributorNonceAllocation(fixture.nonceEvent),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .nonceAllocation
        )
        snapshot = try await persist(
            owner.completeNonceAllocation(),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .manifestAgreement
        )
        snapshot = try await persist(
            owner.acceptManifestProposal(fixture.proposalEvent),
            on: owner
        )
        owner = try await reloadFormation(
            snapshot,
            binding: binding,
            phase: .manifestAgreement
        )
        #expect(
            try await owner.acceptManifestProposal(
                duplicate(fixture.proposalEvent, acceptedAtOffset: 11)
            ) == .ignoredDuplicate(.manifestAgreement)
        )
    }

    @Test("Close a private Tor adapter when its bounded buffer overflows")
    func closeOverflowingTorAdapter() async throws {
        let connection = ScriptedMosaicPrivateAlphaTorConnection()
        let adapter = Runtime.TorWebSocketConnectionAdapter(connection)
        let stream = try await adapter.open(
            maximumIncomingMessageByteCount: 64
        )
        await connection.receive(.text(Data([0x01])))
        await connection.receive(.text(Data([0x02])))
        await connection.receive(.text(Data([0x03])))
        await connection.waitUntilClosed()

        var iterator = stream.makeAsyncIterator()
        #expect(try await iterator.next() == .text(Data([0x01])))
        await #expect(throws: Runtime.Failure.invalidStateTransition) {
            _ = try await iterator.next()
        }
        #expect(await connection.closeCount == 1)
    }

    func persist(
        _ step: Runtime.Step,
        on owner: Runtime.Owner
    ) async throws -> Data {
        guard case let .persist(transition) = step else {
            throw Runtime.Failure.invalidStateTransition
        }
        _ = try await owner.acknowledgePersistence(
            transition,
            exactReadback: transition.replacementSnapshot
        )
        return transition.replacementSnapshot
    }

    private func persistAndPublish(
        _ step: Runtime.Step,
        on owner: Runtime.Owner
    ) async throws -> (
        snapshot: Data,
        event: Runtime.PrivateDeploymentEvent
    ) {
        guard case let .persist(transition) = step else {
            throw Runtime.Failure.invalidStateTransition
        }
        let next = try await owner.acknowledgePersistence(
            transition,
            exactReadback: transition.replacementSnapshot
        )
        guard case let .publishPrivateDeployment(publication) = next else {
            throw Runtime.Failure.invalidStateTransition
        }
        let decoded = try Runtime.PrivateDeploymentEvent(
            canonicalEventBytes: publication.canonicalEventBytes,
            acceptedAtUnixSeconds: 0
        ).decodeCanonicalNostrEvent()
        let event = try Runtime.PrivateDeploymentEvent(
            canonicalEventBytes: publication.canonicalEventBytes,
            acceptedAtUnixSeconds: decoded.template.createdAt
        )
        let receipt = try await publication.publish(
            using: makeRelayCapabilities()
        )
        let snapshot = try await persist(
            owner.acknowledgePrivateDeploymentPublication(
                consuming: receipt
            ),
            on: owner
        )
        return (snapshot, event)
    }

    private func makeRelayCapabilities(
        recording store: MosaicPrivateAlphaRuntimePersistenceStore? = nil
    ) -> Runtime.PrivateDeploymentRelayCapabilities {
        .init(provisionRoutes: { request in
            store?.recordProvisionCall()
            return request.relayEndpointIdentifiers.enumerated().map {
                index,
                endpoint in
                Runtime.PostManifestProvisionedRoute(
                    relayEndpointIdentifier: endpoint,
                    connection: ScriptedMosaicPrivateAlphaTorConnection(),
                    isolationIdentifier: UUID(
                        uuid: (
                            UInt8(index + 1), 0, 0, 0,
                            0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0
                        )
                    )
                )
            }
        })
    }

    private func eventsExcludingSigner(
        _ localEvent: Runtime.PrivateDeploymentEvent,
        from events: [Runtime.PrivateDeploymentEvent]
    ) throws -> [Runtime.PrivateDeploymentEvent] {
        let localSigner = try localEvent.decodeCanonicalNostrEvent().publicKey
        return try events.filter {
            try $0.decodeCanonicalNostrEvent().publicKey != localSigner
        }
    }

    private func duplicate(
        _ event: Runtime.PrivateDeploymentEvent,
        acceptedAtOffset: UInt64
    ) throws -> Runtime.PrivateDeploymentEvent {
        let acceptedAt = event.acceptedAtUnixSeconds.addingReportingOverflow(
            acceptedAtOffset
        )
        guard !acceptedAt.overflow else {
            throw Runtime.Failure.invalidStateTransition
        }
        return try .init(
            canonicalEventBytes: event.canonicalEventBytes,
            acceptedAtUnixSeconds: acceptedAt.partialValue
        )
    }

    func continuation(
        from step: Runtime.Step
    ) throws -> Runtime.PrivateDeploymentContinuation {
        guard case let .recover(.resumePrivateDeployment(continuation)) = step
        else {
            throw Runtime.Failure.invalidStateTransition
        }
        return continuation
    }

    private func reloadFormation(
        _ snapshot: Data,
        binding: Runtime.Binding,
        phase: Runtime.Phase
    ) async throws -> Runtime.Owner {
        let loaded = try Runtime.loadRecovery(
            from: snapshot,
            expectedBinding: binding
        )
        let owner = try Runtime.Owner(claiming: loaded)
        let recovered = try continuation(from: await owner.nextStep())
        #expect(recovered.phase == phase)
        #expect(
            try await owner.resumePrivateDeployment(recovered)
                == .awaitingInput(phase)
        )
        return owner
    }

    func resumedOwner(
        snapshot: Data,
        binding: Runtime.Binding
    ) async throws -> Runtime.Owner {
        let loaded = try Runtime.loadRecovery(
            from: snapshot,
            expectedBinding: binding
        )
        let owner = try Runtime.Owner(claiming: loaded)
        let recovered = try continuation(from: await owner.nextStep())
        _ = try await owner.resumePrivateDeployment(recovered)
        return owner
    }

    func makeSealedSnapshot(
        proof: Runtime.PrivateDeploymentProof,
        binding: Runtime.Binding,
        epoch: UInt64
    ) throws -> Data {
        let state = try Runtime.RecoveryState(
            binding: binding,
            revision: 50,
            discoveryEpochStartUnixSeconds: epoch,
            phase: .walletReservation,
            preManifestDocuments: proof.canonicalDocuments,
            preManifestAbortCause: .none,
            manifestState: .validated(
                privateManifestProposalBytes: Data(
                    proof.proposalValidation.canonicalBody
                ),
                completeManifestBytes: Data(
                    proof.completeManifest.canonicalBytes
                )
            ),
            postManifestJournalState: .uninitialized,
            publicationState: .none,
            terminalState: .active
        )
        try state.validate()
        return try state.canonicalBytes()
    }

    private func replacingMailboxes(
        _ capabilities: Runtime.PostManifestRuntimeCapabilities,
        with mailboxes: Runtime.PostManifestMailboxCapabilities
    ) -> Runtime.PostManifestRuntimeCapabilities {
        .init(
            mailboxes: mailboxes,
            relays: capabilities.relays,
            timing: capabilities.timing,
            admissionPersistence: capabilities.admissionPersistence,
            publicationPersistence: capabilities.publicationPersistence,
            terminalPersistence: capabilities.terminalPersistence,
            maximumPendingInputCount: capabilities.maximumPendingInputCount
        )
    }

    func replacingRelays(
        _ capabilities: Runtime.PostManifestRuntimeCapabilities,
        with relays: Runtime.PostManifestRelayCapabilities
    ) -> Runtime.PostManifestRuntimeCapabilities {
        .init(
            mailboxes: capabilities.mailboxes,
            relays: relays,
            timing: capabilities.timing,
            admissionPersistence: capabilities.admissionPersistence,
            publicationPersistence: capabilities.publicationPersistence,
            terminalPersistence: capabilities.terminalPersistence,
            maximumPendingInputCount: capabilities.maximumPendingInputCount
        )
    }

    func makeWorkingRelayCapabilities(
        from capabilities: Runtime.PostManifestRuntimeCapabilities,
        routeProbe: MosaicPrivateAlphaRuntimePersistenceStore
    ) -> Runtime.PostManifestRelayCapabilities {
        .init(
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
                capabilities.relays.makeSubscriptionIdentifier,
            awaitAnonymousPublicationPermit:
                capabilities.relays.awaitAnonymousPublicationPermit,
            maximumSubscriptionIdentifierByteCount:
                capabilities.relays.maximumSubscriptionIdentifierByteCount,
            maximumPendingEventCount:
                capabilities.relays.maximumPendingEventCount,
            maximumPendingRelayOutputCount:
                capabilities.relays.maximumPendingRelayOutputCount
        )
    }

    func makeContributorHost(
        formation: MosaicPrivateDeploymentFixtures.Formation,
        contributor: OpalFusion.Mosaic.Attempt.ControlIdentity
    ) throws -> Runtime.PostManifestContributorHost {
        let controlIndex = try #require(
            formation.roleElection.roster.controlIdentities
                .firstIndex(of: contributor)
        )
        return .init(
            transactionHost:
                MosaicPrivateAlphaRejectingCompleteTransactionHost(),
            previousOutputSource:
                MosaicPrivateAlphaRejectingPreviousOutputSource(),
            controlSigningKey: formation.controlCandidate(
                for: contributor
            ).signingKey,
            controlEventSigningKey: try MosaicPrivateDeploymentFixtures
                .CandidateKeyMaterial(
                    scalar: UInt8(125 + controlIndex)
                ).signingKey,
            loadSlotSecrets: { _, _ in
                throw Runtime.Failure.invalidStateTransition
            }
        )
    }

    func makeBinding(seed: UInt8) throws -> Runtime.Binding {
        try .init(
            attemptIdentifier: Data(repeating: seed, count: 32),
            generationIdentifier: Data(repeating: seed &+ 1, count: 32),
            materialIdentifier: Data(repeating: seed &+ 2, count: 32)
        )
    }

    func makeSigningCapability(
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
