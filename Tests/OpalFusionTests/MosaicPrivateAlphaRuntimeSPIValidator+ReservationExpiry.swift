// MosaicPrivateAlphaRuntimeSPIValidator+ReservationExpiry.swift

import Foundation
import Synchronization
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

extension MosaicPrivateAlphaRuntimeSPIValidator {
    @Test("Contributor assembly reserves through the validated signing deadline")
    func contributorAssemblyUsesValidatedLeaseExpiration() async throws {
        typealias Bridge = Alpha.PostManifestControlPublicationBridge
        typealias Nostr = OpalFusion.Mosaic.NostrNamespace
        let fixture = try MosaicPrivateDeploymentFixtures.makePrivateAlphaRuntimeProof()
        let roster = fixture.formation.roleElection.roster
        let contributor = try #require(roster.contributors.first)
        let localIdentity = Data(contributor.validatedBytes)
        let binding = try makeBinding(seed: 0xD2)
        let admission = MosaicPrivateAlphaRuntimePersistenceStore()
        let publication = MosaicPrivateAlphaRuntimePersistenceStore()
        let terminal = MosaicPrivateAlphaRuntimePersistenceStore()
        let routes = MosaicPrivateAlphaRuntimePersistenceStore()
        let base = try MosaicPrivateDeploymentFixtures.makeRuntimeCapabilities(
            formation: fixture.formation, localControlIdentity: localIdentity,
            admissionStore: admission, publicationStore: publication,
            terminalStore: terminal, routeStore: routes
        )
        let connections = Mutex<[ScriptedMosaicPrivateAlphaTorConnection]>([])
        let relays = Runtime.PostManifestRelayCapabilities(
            provisionRoutes: { requests in
                requests.map { request in
                    .init(recipientEventIdentity: request.recipientEventIdentity,
                          routes: request.relayEndpointIdentifiers.map { endpoint in
                        let connection = ScriptedMosaicPrivateAlphaTorConnection()
                        connections.withLock { $0.append(connection) }
                        return .init(relayEndpointIdentifier: endpoint,
                                     connection: connection, isolationIdentifier: UUID())
                    })
                }
            },
            makeSubscriptionIdentifier: base.relays.makeSubscriptionIdentifier,
            maximumSubscriptionIdentifierByteCount: base.relays.maximumSubscriptionIdentifierByteCount
        )
        let capabilities = replacingRelays(base, with: relays)
        let owner = try await resumedOwner(
            snapshot: makeSealedSnapshot(proof: fixture.proof, binding: binding, epoch: fixture.epoch),
            binding: binding
        )
        _ = try await persist(owner.preparePostManifestRuntime(
            localControlIdentity: localIdentity, capabilities: capabilities
        ), on: owner)
        let construction = try await owner.makePostManifestConstruction(localControlIdentity: localIdentity)
        let deadlines = construction.completeManifest.core.deadlines
        let expectedExpiration = construction.privateManifest.reservationLeaseExpirationUnixSeconds
        let bootstrap = construction.bootstrap
        let conductorBootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: bootstrap.validatedAttempt,
            attemptIdentifier: bootstrap.attemptIdentifier,
            generationIdentifier: bootstrap.generationIdentifier,
            materialIdentifier: bootstrap.materialIdentifier,
            localControlIdentity: roster.conductor,
            proposalValidation: bootstrap.proposalValidation
        )
        let conductorIndex = try #require(roster.controlIdentities.firstIndex(of: roster.conductor))
        let manifests = Mutex<[Nostr.Event]>([])
        let bridge = try Bridge(
            context: .init(validating: construction.completeManifest, against: conductorBootstrap),
            controlSigningKey: fixture.formation.controlCandidate(for: roster.conductor).signingKey,
            eventSigningKey: try MosaicPrivateDeploymentFixtures.CandidateKeyMaterial(
                scalar: UInt8(125 + conductorIndex)
            ).signingKey,
            recipients: capabilities.mailboxes.controlMailboxes.map {
                .init(controlIdentity: .init(validatedBytes: Array($0.controlIdentity)),
                      eventVerificationKey: $0.eventVerificationKey)
            },
            dependencies: .init(makeLayerTimestamps: { _ in
                try .init(phaseStartUnixSeconds: deadlines.phaseStart,
                          currentUnixSeconds: deadlines.phaseStart + 1,
                          sealCreatedAt: deadlines.phaseStart,
                          giftWrapCreatedAt: deadlines.phaseStart)
            }, handoffGiftWrapBatch: { batch in
                let recipient = try #require(batch.recipients.first { $0.controlIdentity == contributor })
                manifests.withLock { $0.append(recipient.giftWrap.event) }
            })
        )
        try await bridge.publishManifest(expiryUnixSeconds: deadlines.walletReservation)
        let rejectingHost = MosaicPrivateAlphaRejectingCompleteTransactionHost()
        let existingHost = try makeContributorHost(formation: fixture.formation, contributor: contributor)
        let execution = try await construction.makeContributorExecution(
            host: .init(transactionHost: rejectingHost,
                        previousOutputSource: existingHost.previousOutputSource,
                        controlSigningKey: existingHost.controlSigningKey,
                        controlEventSigningKey: existingHost.controlEventSigningKey,
                        loadSlotSecrets: existingHost.loadSlotSecrets,
                        installOrLoadAuthorizationRecoveryStates: existingHost.installOrLoadAuthorizationRecoveryStates),
            capabilities: capabilities
        )
        try await execution.start()
        do {
            let opened = connections.withLock { $0 }
            #expect(opened.count == Alpha.relayCount)
            let events = manifests.withLock { $0 }
            #expect(!events.isEmpty)
            for connection in opened {
                let subscription = try #require(try await connection.sentTexts.compactMap { text -> String? in
                    guard let frame = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [Any],
                          frame.first as? String == "REQ" else { return nil }
                    return frame[1] as? String
                }.first)
                for event in events {
                    let encoded = try Nostr.EventCodec.encode(event, limits: (try Alpha.PostManifestNIP59Transport.codingLimits).event)
                    let frame = "[\"EVENT\"," + Nostr.EventCodec.encodeString(subscription)
                        + "," + String(decoding: encoded, as: UTF8.self) + "]"
                    await connection.receive(.text(Data(frame.utf8)))
                }
            }
            let limit = ContinuousClock.now.advanced(by: .seconds(2))
            while await rejectingHost.reservationRequests.isEmpty, ContinuousClock.now < limit {
                try await Task.sleep(for: .milliseconds(10))
            }
            let requests = await rejectingHost.reservationRequests
            let request = try #require(requests.first)
            #expect(requests.count == 1)
            #expect(expectedExpiration == deadlines.bchSigning)
            #expect(request.expiresAt == Date(timeIntervalSince1970: TimeInterval(expectedExpiration)))
            #expect(request.expiresAt != Date(timeIntervalSince1970: TimeInterval(deadlines.walletReservation)))
            await execution.stop()
        } catch {
            await execution.stop()
            throw error
        }
    }
}
