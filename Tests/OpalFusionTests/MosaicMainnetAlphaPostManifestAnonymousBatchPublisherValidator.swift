// MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha anonymous batch relay publication", .serialized)
struct MosaicMainnetAlphaPostManifestAnonymousBatchPublisherValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Attempt = OpalFusion.Mosaic.Attempt
    typealias Bridge = Alpha.PostManifestAnonymousPublicationBridge
    typealias Coordinator = Alpha.ReservationCoordinator
    typealias ExecutionFixture = MosaicMainnetAlphaExecutionFixtures
    typealias Fixture = MosaicMainnetAlphaAdmissionLedgerFixtures
    typealias LocalAttempt = OpalFusion.Mosaic.LocalAttempt
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Publisher = Alpha.PostManifestAnonymousBatchPublisher
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker
    typealias Transport = Alpha.PostManifestNIP59Transport

    private static let currentUnixSeconds: UInt64 = 1_800_000_100
    private static let expiryUnixSeconds: UInt64 = 1_800_000_200

    private enum ProbeFailure: Error {
        case injected
        case invalidRequests
    }

    private struct ExactRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating
    {
        let expectedDigest: [UInt8]
        let expectedEndpoints: Set<Tracker.Endpoint>

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [Tracker.Endpoint]
        ) throws {
            guard manifestRelaySetDigest == expectedDigest,
                  Set(endpoints) == expectedEndpoints else {
                throw ProbeFailure.injected
            }
        }
    }

    private struct SharedFixture: Sendable {
        let context: Bridge.Context
        let conductorContext: Bridge.Context
        let foreignContext: Bridge.Context
        let material: Alpha.LocalContributionMaterial
        let foreignMaterial: Alpha.LocalContributionMaterial
        let materialBinding: Bridge.MaterialBinding
        let componentBatch: Bridge.GiftWrapBatch
        let signatureBatch: Bridge.GiftWrapBatch
    }

    private struct RouteAllocation {
        let groups: [Publisher.RecipientRouteGroup]
        let connections: [
            Data: [ScriptedMosaicTorWebSocketConnection]
        ]
    }

    private actor BatchCapture {
        private var batches: [Bridge.GiftWrapBatch] = []

        func handoff(_ batch: Bridge.GiftWrapBatch) {
            batches.append(batch)
        }

        func values() -> [Bridge.GiftWrapBatch] {
            batches
        }
    }

    private actor CompletionProbe {
        private(set) var isCompleted = false

        func markCompleted() {
            isCompleted = true
        }
    }

    private actor RouteProviderProbe {
        enum Behavior: Sendable {
            case provide
            case fail
            case suspendUntilCancelled
        }

        private let expectedRequests: [Publisher.RecipientRouteRequest]
        private let groups: [Publisher.RecipientRouteGroup]
        private let behavior: Behavior
        private let suspension: MosaicRuntimeCoordinatorSuspensionProbe?
        private(set) var callCount = 0

        init(
            expectedRequests: [Publisher.RecipientRouteRequest],
            groups: [Publisher.RecipientRouteGroup],
            behavior: Behavior = .provide,
            suspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
        ) {
            self.expectedRequests = expectedRequests
            self.groups = groups
            self.behavior = behavior
            self.suspension = suspension
        }

        func provide(
            _ requests: [Publisher.RecipientRouteRequest]
        ) async throws -> [Publisher.RecipientRouteGroup] {
            callCount += 1
            guard requests == expectedRequests else {
                throw ProbeFailure.invalidRequests
            }
            switch behavior {
            case .provide:
                return groups
            case .fail:
                await Self.close(groups)
                throw ProbeFailure.injected
            case .suspendUntilCancelled:
                await suspension?.suspendIfArmed()
                do {
                    try Task.checkCancellation()
                } catch {
                    await Self.close(groups)
                    throw error
                }
                return groups
            }
        }

        private static func close(
            _ groups: [Publisher.RecipientRouteGroup]
        ) async {
            await withTaskGroup(of: Void.self) { group in
                for route in groups.flatMap(\.routes) {
                    group.addTask { await route.connection.close() }
                }
            }
        }
    }

    private actor PermitProbe {
        enum Behavior: Sendable, Equatable {
            case allow
            case fail
            case suspendThenAllow
            case suspendThenFail
            case suspendThenFailRecipient(Data)
        }

        private let behavior: Behavior
        private let suspension: MosaicRuntimeCoordinatorSuspensionProbe?
        private(set) var requests: [Publisher.PublicationPermitRequest] = []

        init(
            behavior: Behavior = .allow,
            suspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil
        ) {
            self.behavior = behavior
            self.suspension = suspension
        }

        func awaitPermit(
            _ request: Publisher.PublicationPermitRequest
        ) async throws {
            requests.append(request)
            switch behavior {
            case .allow:
                return
            case .fail:
                throw ProbeFailure.injected
            case .suspendThenAllow, .suspendThenFail:
                await suspension?.suspendIfArmed()
                try Task.checkCancellation()
                if behavior == .suspendThenFail {
                    throw ProbeFailure.injected
                }
            case let .suspendThenFailRecipient(recipient):
                guard request.recipientEventIdentity == recipient else {
                    return
                }
                await suspension?.suspendIfArmed()
                try Task.checkCancellation()
                throw ProbeFailure.injected
            }
        }
    }

    private static let sharedFixtureTask = Task {
        try await makeSharedFixture()
    }

    init() throws {
        try MosaicMainnetAlphaFixtures.requireAuthorizationEvaluators()
    }

    @Test("Reject incompatible material, manifest, and coding configuration")
    func rejectInvalidConfiguration() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let relaySelection = try makeRelaySelection(context: fixture.context)
        let provider: Publisher.RouteProvider = { _ in [] }
        let permit: Publisher.PublicationPermitProvider = { _ in }

        #expect(
            throws: Publisher.InitializationError.localPeerIsNotContributor
        ) {
            _ = try Publisher(
                context: fixture.conductorContext,
                material: fixture.material,
                relaySelection: relaySelection,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider,
                awaitPublicationPermit: permit
            )
        }
        #expect(throws: Publisher.InitializationError.localMaterialMismatch) {
            _ = try Publisher(
                context: fixture.context,
                material: fixture.foreignMaterial,
                relaySelection: relaySelection,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider,
                awaitPublicationPermit: permit
            )
        }
        #expect(
            throws: Publisher.InitializationError
                .manifestRelaySelectionMismatch
        ) {
            _ = try Publisher(
                context: fixture.context,
                material: fixture.material,
                relaySelection: makeRelaySelection(
                    context: fixture.context,
                    digest: [UInt8](repeating: 0xFE, count: 32)
                ),
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider,
                awaitPublicationPermit: permit
            )
        }
        #expect(throws: Publisher.InitializationError.invalidOutputBufferLimit) {
            _ = try Publisher(
                context: fixture.context,
                material: fixture.material,
                relaySelection: relaySelection,
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 0,
                provideRoutes: provider,
                awaitPublicationPermit: permit
            )
        }

        let incompatibleEventLimits = try Nostr.EventCodingLimits(
            maximumEventJSONByteCount: Alpha.nip59MaximumGiftWrapJSONByteCount,
            maximumTagCount: 2,
            maximumTagElementCount: 2,
            maximumStringByteCount: Alpha.nip59GiftWrapContentByteCount
        )
        let incompatibleLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: Alpha.nip59MaximumPublicationFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: incompatibleEventLimits
        )
        #expect(throws: Publisher.InitializationError.incompatibleCodingLimits) {
            _ = try Publisher(
                context: fixture.context,
                material: fixture.material,
                relaySelection: relaySelection,
                codingLimits: incompatibleLimits,
                maximumPendingRelayOutputCount: 4,
                provideRoutes: provider,
                awaitPublicationPermit: permit
            )
        }
    }

    @Test(
        "Publish all component recipients after complete route preflight",
        .timeLimit(.minutes(5))
    )
    func publishComponentBatch() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.componentBatch
        let allocation = makeRouteAllocation(batch: batch)
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups.reversed()
        )
        let permitProbe = PermitProbe()
        let publisher = try makePublisher(
            fixture: fixture,
            routeProbe: routeProbe,
            permitProbe: permitProbe
        )
        let completion = CompletionProbe()
        let finalConnection = try #require(
            allocation.connections[batch.recipients.last!
                .recipientEventIdentity]?.last
        )
        await finalConnection.suspendNextClose()

        let publication = Task {
            try await publisher.publish(batch)
            await completion.markCompleted()
        }
        await waitForEverySend(batch: batch, allocation: allocation)
        for recipient in batch.recipients {
            let connections = try #require(
                allocation.connections[recipient.recipientEventIdentity]
            )
            await connections[0].receive(
                acknowledgement(for: recipient.giftWrap, accepted: true)
            )
            await connections[1].receive(
                acknowledgement(for: recipient.giftWrap, accepted: true)
            )
        }

        await finalConnection.waitUntilCloseSuspends()
        #expect(await completion.isCompleted == false)
        await finalConnection.resumeClose()
        try await publication.value

        #expect(await routeProbe.callCount == 1)
        let permitRequests = await permitProbe.requests
        #expect(permitRequests.count == Alpha.componentCountPerContributor)
        #expect(Set(permitRequests.map(\.recipientEventIdentity)).count
            == Alpha.componentCountPerContributor)
        #expect(
            Set(permitRequests.map(\.recipientEventIdentity))
                == Set(batch.recipients.map(\.recipientEventIdentity))
        )
        #expect(permitRequests.allSatisfy {
            $0.kind == .components
        })
        for recipient in batch.recipients {
            let connections = try #require(
                allocation.connections[recipient.recipientEventIdentity]
            )
            let frames = await frames(from: connections)
            #expect(frames.count == Alpha.relayCount)
            #expect(Set(frames).count == 1)
            for connection in connections {
                #expect(await connection.openCount == 1)
                #expect(await connection.closeCount == 1)
            }
        }
    }

    @Test(
        "Gate each signature recipient on its publication permit",
        .timeLimit(.minutes(2))
    )
    func gateSignaturePublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.signatureBatch
        #expect(batch.recipients.count == 1)
        let allocation = makeRouteAllocation(batch: batch)
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups
        )
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let permitProbe = PermitProbe(
            behavior: .suspendThenAllow,
            suspension: suspension
        )
        let publisher = try makePublisher(
            fixture: fixture,
            routeProbe: routeProbe,
            permitProbe: permitProbe
        )
        let publication = Task { try await publisher.publish(batch) }
        await suspension.waitUntilSuspended()

        #expect(await routeProbe.callCount == 1)
        for connection in allocation.groups.flatMap(\.routes)
            .map(\.connection) {
            let scripted = try #require(
                connection as? ScriptedMosaicTorWebSocketConnection
            )
            #expect(await scripted.openCount == 0)
            #expect(await scripted.sentTexts.isEmpty)
        }

        await suspension.resume()
        await waitForEverySend(batch: batch, allocation: allocation)
        let recipient = try #require(batch.recipients.first)
        let connections = try #require(
            allocation.connections[recipient.recipientEventIdentity]
        )
        await connections[0].receive(
            acknowledgement(for: recipient.giftWrap, accepted: true)
        )
        await connections[1].receive(
            acknowledgement(for: recipient.giftWrap, accepted: true)
        )
        try await publication.value

        #expect(await permitProbe.requests == [
            .init(
                kind: .bchSignatures,
                recipientEventIdentity: recipient.recipientEventIdentity
            ),
        ])
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test("Retain sealed purpose and exact recipient allocation")
    func retainSealedBatchBindings() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let componentBatch = fixture.componentBatch
        let signatureBatch = fixture.signatureBatch

        #expect(componentBatch.kind == .components)
        #expect(signatureBatch.kind == .bchSignatures)
        #expect(
            componentBatch.isBound(
                to: fixture.context,
                materialBinding: fixture.materialBinding
            )
        )
        #expect(
            signatureBatch.isBound(
                to: fixture.context,
                materialBinding: fixture.materialBinding
            )
        )
        #expect(
            componentBatch.recipients.count
                == Alpha.componentCountPerContributor
        )
        let inputRecipients = Set(
            fixture.material.slots.compactMap { slot -> Data? in
                guard case .input = slot.component.payload else { return nil }
                return Data(slot.recipientEventIdentity)
            }
        )
        #expect(
            Set(signatureBatch.recipients.map(\.recipientEventIdentity))
                == inputRecipients
        )
        for batch in [componentBatch, signatureBatch] {
            #expect(
                Set(batch.recipients.map(\.recipientEventIdentity)).count
                    == batch.recipients.count
            )
            for recipient in batch.recipients {
                #expect(recipient.giftWrap.event.template.tags == [[
                    "p",
                    Nostr.EventCodec.hexadecimal(
                        recipient.recipientEventIdentity
                    ),
                ]])
            }
        }
    }

    @Test("Reject a sealed batch from another material before routing")
    func rejectForeignMaterialBatch() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.componentBatch
        let allocation = makeRouteAllocation(batch: batch)
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups
        )
        let permitProbe = PermitProbe()
        let publisher = try Publisher(
            context: fixture.foreignContext,
            material: fixture.foreignMaterial,
            relaySelection: makeRelaySelection(
                context: fixture.foreignContext
            ),
            codingLimits: relayLimits,
            maximumPendingRelayOutputCount: 4,
            provideRoutes: { requests in
                try await routeProbe.provide(requests)
            },
            awaitPublicationPermit: { request in
                try await permitProbe.awaitPermit(request)
            }
        )

        await #expect(throws: Publisher.Failure.batchContextMismatch) {
            try await publisher.publish(batch)
        }
        #expect(await routeProbe.callCount == 0)
        #expect(await permitProbe.requests.isEmpty)
        try await assertNoExposure(allocation)
    }

    @Test("Reject incomplete or reused route allocations before permits")
    func rejectInvalidRouteAllocations() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.componentBatch

        let duplicateAllocation = makeRouteAllocation(batch: batch)
        var duplicateGroups = duplicateAllocation.groups
        let omittedDuplicateGroup = duplicateGroups.removeLast()
        duplicateGroups.append(duplicateGroups[0])
        let suspendedDuplicateClose = try #require(
            duplicateAllocation.connections[
                duplicateGroups[0].recipientEventIdentity
            ]?.first
        )
        await suspendedDuplicateClose.suspendNextClose()
        let duplicateRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: duplicateGroups
        )
        let duplicatePermitProbe = PermitProbe()
        let duplicatePublisher = try makePublisher(
            fixture: fixture,
            routeProbe: duplicateRouteProbe,
            permitProbe: duplicatePermitProbe
        )
        let duplicateCompletion = CompletionProbe()
        let duplicatePublication = Task { () -> Publisher.Failure? in
            do {
                try await duplicatePublisher.publish(batch)
                await duplicateCompletion.markCompleted()
                return nil
            } catch let failure as Publisher.Failure {
                await duplicateCompletion.markCompleted()
                return failure
            } catch {
                await duplicateCompletion.markCompleted()
                return nil
            }
        }
        await suspendedDuplicateClose.waitUntilCloseSuspends()
        #expect(await duplicateCompletion.isCompleted == false)
        await suspendedDuplicateClose.resumeClose()
        #expect(
            await duplicatePublication.value
                == Publisher.Failure.routeAllocationMismatch
        )
        #expect(await duplicatePermitProbe.requests.isEmpty)
        for route in duplicateGroups.flatMap(\.routes) {
            let connection = try #require(
                route.connection as? ScriptedMosaicTorWebSocketConnection
            )
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }
        for connection in try #require(
            duplicateAllocation.connections[
                omittedDuplicateGroup.recipientEventIdentity
            ]
        ) {
            #expect(await connection.closeCount == 0)
        }

        let foreignAllocation = makeRouteAllocation(batch: batch)
        var foreignGroups = foreignAllocation.groups
        let finalForeignGroup = foreignGroups.removeLast()
        foreignGroups.append(
            .init(
                recipientEventIdentity: Data(repeating: 0xFE, count: 32),
                routes: finalForeignGroup.routes
            )
        )
        let foreignRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: foreignGroups
        )
        let foreignPermitProbe = PermitProbe()
        let foreignPublisher = try makePublisher(
            fixture: fixture,
            routeProbe: foreignRouteProbe,
            permitProbe: foreignPermitProbe
        )
        await #expect(throws: Publisher.Failure.routeAllocationMismatch) {
            try await foreignPublisher.publish(batch)
        }
        #expect(await foreignPermitProbe.requests.isEmpty)
        for route in foreignGroups.flatMap(\.routes) {
            let connection = try #require(
                route.connection as? ScriptedMosaicTorWebSocketConnection
            )
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }

        let missingAllocation = makeRouteAllocation(batch: batch)
        let missingGroups = Array(missingAllocation.groups.dropLast())
        let missingRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: missingGroups
        )
        let missingPermitProbe = PermitProbe()
        let missingPublisher = try makePublisher(
            fixture: fixture,
            routeProbe: missingRouteProbe,
            permitProbe: missingPermitProbe
        )
        await #expect(throws: Publisher.Failure.routeAllocationMismatch) {
            try await missingPublisher.publish(batch)
        }
        #expect(await missingPermitProbe.requests.isEmpty)
        for route in missingGroups.flatMap(\.routes) {
            let connection = try #require(
                route.connection as? ScriptedMosaicTorWebSocketConnection
            )
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }
        let omittedIdentity = try #require(
            missingAllocation.groups.last?.recipientEventIdentity
        )
        for connection in try #require(
            missingAllocation.connections[omittedIdentity]
        ) {
            #expect(await connection.closeCount == 0)
        }

        let incompleteAllocation = makeRouteAllocation(batch: batch)
        var incompleteGroups = incompleteAllocation.groups
        let final = incompleteGroups.removeLast()
        incompleteGroups.append(
            .init(
                recipientEventIdentity: final.recipientEventIdentity,
                routes: Array(final.routes.dropLast())
            )
        )
        let incompleteRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: incompleteGroups
        )
        let incompletePermitProbe = PermitProbe()
        let incompletePublisher = try makePublisher(
            fixture: fixture,
            routeProbe: incompleteRouteProbe,
            permitProbe: incompletePermitProbe
        )
        await #expect(throws: Publisher.Failure.publisherConstructionFailed) {
            try await incompletePublisher.publish(batch)
        }
        #expect(await incompletePermitProbe.requests.isEmpty)
        for route in incompleteGroups.flatMap(\.routes) {
            let connection = try #require(
                route.connection as? ScriptedMosaicTorWebSocketConnection
            )
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
            #expect(await connection.sentTexts.isEmpty)
        }

        let reusedAllocation = makeRouteAllocation(batch: batch)
        var reusedGroups = reusedAllocation.groups
        let reusedConnection = try #require(
            reusedAllocation.connections[
                reusedGroups[0].recipientEventIdentity
            ]?.first
        )
        let omittedConnection = try #require(
            reusedAllocation.connections[
                reusedGroups[1].recipientEventIdentity
            ]?.first
        )
        var secondRoutes = reusedGroups[1].routes
        secondRoutes[0] = .init(
            endpoint: secondRoutes[0].endpoint,
            connection: reusedConnection
        )
        reusedGroups[1] = .init(
            recipientEventIdentity: reusedGroups[1].recipientEventIdentity,
            routes: secondRoutes
        )
        let reusedRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: reusedGroups
        )
        let reusedPermitProbe = PermitProbe()
        let reusedPublisher = try makePublisher(
            fixture: fixture,
            routeProbe: reusedRouteProbe,
            permitProbe: reusedPermitProbe
        )
        await #expect(throws: Publisher.Failure.duplicateConnection) {
            try await reusedPublisher.publish(batch)
        }
        #expect(await reusedPermitProbe.requests.isEmpty)
        #expect(await omittedConnection.closeCount == 0)
        for route in reusedGroups.flatMap(\.routes) {
            let connection = try #require(
                route.connection as? ScriptedMosaicTorWebSocketConnection
            )
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Map permit failure and cancellation without event exposure",
        .timeLimit(.minutes(2))
    )
    func rejectOrCancelPermit() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.signatureBatch

        let failureAllocation = makeRouteAllocation(batch: batch)
        let failureRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: failureAllocation.groups
        )
        let failureSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await failureSuspension.arm()
        let failurePermitProbe = PermitProbe(
            behavior: .suspendThenFail,
            suspension: failureSuspension
        )
        let failurePublisher = try makePublisher(
            fixture: fixture,
            routeProbe: failureRouteProbe,
            permitProbe: failurePermitProbe
        )
        let failedPublication = Task {
            try await failurePublisher.publish(batch)
        }
        await failureSuspension.waitUntilSuspended()
        try await assertNoExposure(failureAllocation)
        await failureSuspension.resume()
        await #expect(throws: Publisher.Failure.publicationPermitFailed) {
            try await failedPublication.value
        }
        try await assertClosedWithoutExposure(failureAllocation)

        let cancellationAllocation = makeRouteAllocation(batch: batch)
        let cancellationRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: cancellationAllocation.groups
        )
        let cancellationSuspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await cancellationSuspension.arm()
        let cancellationPermitProbe = PermitProbe(
            behavior: .suspendThenAllow,
            suspension: cancellationSuspension
        )
        let cancellationPublisher = try makePublisher(
            fixture: fixture,
            routeProbe: cancellationRouteProbe,
            permitProbe: cancellationPermitProbe
        )
        let cancelledPublication = Task {
            try await cancellationPublisher.publish(batch)
        }
        await cancellationSuspension.waitUntilSuspended()
        cancelledPublication.cancel()
        await cancellationSuspension.resume()
        await #expect(throws: Publisher.Failure.cancelled) {
            try await cancelledPublication.value
        }
        try await assertClosedWithoutExposure(cancellationAllocation)
    }

    @Test(
        "Preserve permit failure while cancelling active siblings",
        .timeLimit(.minutes(2))
    )
    func preservePermitFailurePrecedence() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.componentBatch
        let selectedRecipient = batch.recipients.last!
        let allocation = makeRouteAllocation(batch: batch)
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups
        )
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let permitProbe = PermitProbe(
            behavior: .suspendThenFailRecipient(
                selectedRecipient.recipientEventIdentity
            ),
            suspension: suspension
        )
        let publisher = try makePublisher(
            fixture: fixture,
            routeProbe: routeProbe,
            permitProbe: permitProbe
        )
        let activeSibling = batch.recipients[0]
        let activeSiblingConnections = try #require(
            allocation.connections[activeSibling.recipientEventIdentity]
        )
        await activeSiblingConnections[0].suspendNextClose()
        let completion = CompletionProbe()
        let publication = Task { () -> Publisher.Failure? in
            do {
                try await publisher.publish(batch)
                await completion.markCompleted()
                return nil
            } catch let failure as Publisher.Failure {
                await completion.markCompleted()
                return failure
            } catch {
                await completion.markCompleted()
                return nil
            }
        }
        await suspension.waitUntilSuspended()
        for connection in activeSiblingConnections {
            await connection.waitUntilSentTextCount(1)
        }

        await suspension.resume()
        await activeSiblingConnections[0].waitUntilCloseSuspends()
        #expect(await completion.isCompleted == false)
        await activeSiblingConnections[0].resumeClose()
        #expect(
            await publication.value
                == Publisher.Failure.publicationPermitFailed
        )
        let selectedConnections = try #require(
            allocation.connections[
                selectedRecipient.recipientEventIdentity
            ]
        )
        for connection in selectedConnections {
            #expect(await connection.openCount == 0)
            #expect(await connection.sentTexts.isEmpty)
        }
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.closeCount == 1)
            }
        }
    }

    @Test(
        "Fail or cancel route provisioning before event exposure",
        .timeLimit(.minutes(2))
    )
    func cancelRouteProvisioning() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.signatureBatch

        let failingAllocation = makeRouteAllocation(batch: batch)
        let failingRouteProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: failingAllocation.groups,
            behavior: .fail
        )
        let failingPermitProbe = PermitProbe()
        let failingPublisher = try makePublisher(
            fixture: fixture,
            routeProbe: failingRouteProbe,
            permitProbe: failingPermitProbe
        )
        await #expect(throws: Publisher.Failure.routeProvisioningFailed) {
            try await failingPublisher.publish(batch)
        }
        #expect(await failingPermitProbe.requests.isEmpty)
        try await assertClosedWithoutExposure(failingAllocation)

        let allocation = makeRouteAllocation(batch: batch)
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups,
            behavior: .suspendUntilCancelled,
            suspension: suspension
        )
        let permitProbe = PermitProbe()
        let publisher = try makePublisher(
            fixture: fixture,
            routeProbe: routeProbe,
            permitProbe: permitProbe
        )
        let publication = Task { try await publisher.publish(batch) }
        await suspension.waitUntilSuspended()

        publication.cancel()
        await suspension.resume()
        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        #expect(await permitProbe.requests.isEmpty)
        try await assertClosedWithoutExposure(allocation)
    }

    @Test(
        "Reject cancellation before requesting routes",
        .timeLimit(.minutes(2))
    )
    func rejectPrecancelledPublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.signatureBatch
        let allocation = makeRouteAllocation(batch: batch)
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups
        )
        let permitProbe = PermitProbe()
        let publisher = try makePublisher(
            fixture: fixture,
            routeProbe: routeProbe,
            permitProbe: permitProbe
        )
        let entryGate = MosaicRuntimeCoordinatorSuspensionProbe()
        await entryGate.arm()
        let publication = Task {
            await entryGate.suspendIfArmed()
            return try await publisher.publish(batch)
        }
        await entryGate.waitUntilSuspended()

        publication.cancel()
        await entryGate.resume()
        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        #expect(await routeProbe.callCount == 0)
        #expect(await permitProbe.requests.isEmpty)
        try await assertNoExposure(allocation)
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.closeCount == 0)
            }
        }
    }

    @Test(
        "Cancel every sibling when one component recipient misses quorum",
        .timeLimit(.minutes(2))
    )
    func rejectRecipientQuorumFailure() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.componentBatch
        let allocation = makeRouteAllocation(batch: batch)
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups
        )
        let permitProbe = PermitProbe()
        let publisher = try makePublisher(
            fixture: fixture,
            routeProbe: routeProbe,
            permitProbe: permitProbe
        )
        let completion = CompletionProbe()
        let publication = Task { () -> Publisher.Failure? in
            do {
                try await publisher.publish(batch)
                await completion.markCompleted()
                return nil
            } catch let failure as Publisher.Failure {
                await completion.markCompleted()
                return failure
            } catch {
                await completion.markCompleted()
                Issue.record("Unexpected publication error: \(error)")
                return nil
            }
        }
        await waitForEverySend(batch: batch, allocation: allocation)

        let rejectedRecipient = batch.recipients[0]
        let rejectedConnections = try #require(
            allocation.connections[
                rejectedRecipient.recipientEventIdentity
            ]
        )
        let siblingConnection = try #require(
            allocation.connections[
                batch.recipients[1].recipientEventIdentity
            ]?.first
        )
        await siblingConnection.suspendNextClose()
        await rejectedConnections[0].receive(
            acknowledgement(
                for: rejectedRecipient.giftWrap,
                accepted: true
            )
        )
        await rejectedConnections[1].receive(
            acknowledgement(
                for: rejectedRecipient.giftWrap,
                accepted: false
            )
        )
        await rejectedConnections[2].receive(
            acknowledgement(
                for: rejectedRecipient.giftWrap,
                accepted: false
            )
        )

        await siblingConnection.waitUntilCloseSuspends()
        #expect(await completion.isCompleted == false)
        await siblingConnection.resumeClose()
        #expect(
            await publication.value
                == Publisher.Failure.recipientPublicationFailed
        )
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.closeCount == 1)
            }
        }
    }

    @Test(
        "Cancel active signature publication and drain every route",
        .timeLimit(.minutes(2))
    )
    func cancelActivePublication() async throws {
        let fixture = try await Self.sharedFixtureTask.value
        let batch = fixture.signatureBatch
        let allocation = makeRouteAllocation(batch: batch)
        let routeProbe = RouteProviderProbe(
            expectedRequests: routeRequests(batch),
            groups: allocation.groups
        )
        let permitProbe = PermitProbe()
        let publisher = try makePublisher(
            fixture: fixture,
            routeProbe: routeProbe,
            permitProbe: permitProbe
        )
        let publication = Task { try await publisher.publish(batch) }
        await waitForEverySend(batch: batch, allocation: allocation)

        publication.cancel()
        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.closeCount == 1)
            }
        }
    }

    private static func makeSharedFixture() async throws -> SharedFixture {
        let prepared = try await ExecutionFixture.prepare()
        let material = prepared.localMaterial
        let componentTokens = prepared.localAuthorizationValidation
            .componentAuthorizationTokens
        let componentPublications = try material.slots.map { slot in
            Coordinator.LocalAnonymousComponentPublication(
                slot: slot.slot,
                recipientEventIdentity: slot.recipientEventIdentity,
                payload: try .init(
                    roundIdentifier: material.manifest.core.roundIdentifier,
                    authorizationToken: componentTokens[slot.slot],
                    component: slot.component
                )
            )
        }
        let componentValidation = try Bridge.ComponentValidation(
            validating: componentPublications,
            material: material,
            runtimeContext: prepared.session.context
        )
        let transcript = prepared.materialized.prepared.transcript
        let transcriptInclusion = try LocalAttempt
            .TranscriptInclusionValidation(
                attemptIdentifier: material.attemptIdentifier,
                generationIdentifier: material.generationIdentifier,
                contributor: material.contributor,
                materialIdentifier: material.materialIdentifier,
                transcript: transcript,
                using: material
            )
        let signaturePublications = try Alpha.LocalBCHSignatureBuilder.build(
            finalizedTransaction: prepared.localFinalizedTransaction,
            signingRequest: prepared.signingRequest,
            transcript: transcript,
            material: material,
            authorizationValidation: prepared.localAuthorizationValidation
        )
        let signatureValidation = try Bridge.BCHSignatureValidation(
            validating: signaturePublications,
            transcriptInclusion: transcriptInclusion,
            material: material,
            runtimeContext: prepared.session.context
        )
        let context = try Bridge.Context(
            validating: material,
            against: prepared.session.context
        )
        let conductorBootstrap = Alpha.PostManifestRuntimeDriver.Bootstrap(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: prepared.admission.election
            ),
            attemptIdentifier: prepared.admission.attemptIdentifier,
            generationIdentifier: prepared.admission.generationIdentifier,
            materialIdentifier: prepared.admission.materialIdentifier,
            localControlIdentity:
                prepared.admission.manifest.core.roster.conductor,
            proposalValidation: prepared.admission.proposalValidation
        )
        let conductorContext = try Bridge.Context(
            validating: prepared.admission.manifest,
            against: conductorBootstrap
        )
        let foreignMaterial = try #require(
            prepared.materialized.materials.first {
                $0.key != material.contributor
            }?.value
        )
        let foreignSession = try Alpha.RuntimeSession(
            validatedAttempt: Fixture.makeValidatedAttempt(
                election: prepared.admission.election
            ),
            attemptIdentifier: foreignMaterial.attemptIdentifier,
            generationIdentifier: foreignMaterial.generationIdentifier,
            materialIdentifier: foreignMaterial.materialIdentifier,
            localControlIdentity: foreignMaterial.contributor,
            proposalValidation: prepared.admission.proposalValidation
        )
        let foreignContext = try Bridge.Context(
            validating: foreignMaterial,
            against: foreignSession.context
        )

        let capture = BatchCapture()
        let bridge = try Bridge(
            context: context,
            material: material,
            dependencies: .init(
                makeLayerTimestamps: { _ in
                    try .init(
                        phaseStartUnixSeconds:
                            context.phaseStartUnixSeconds,
                        currentUnixSeconds: Self.currentUnixSeconds,
                        sealCreatedAt: Self.currentUnixSeconds - 2,
                        giftWrapCreatedAt: Self.currentUnixSeconds - 1
                    )
                },
                handoffGiftWrapBatch: { batch in
                    await capture.handoff(batch)
                }
            )
        )
        try await bridge.publishComponents(
            componentValidation,
            expiryUnixSeconds: expiryUnixSeconds
        )
        try await bridge.publishBCHSignatures(
            signatureValidation,
            expiryUnixSeconds: expiryUnixSeconds
        )
        let batches = await capture.values()
        guard batches.count == 2,
              batches[0].kind == .components,
              batches[1].kind == .bchSignatures else {
            throw ProbeFailure.injected
        }
        let materialBinding = Bridge.MaterialBinding(material: material)
        guard batches.allSatisfy({
            $0.isBound(to: context, materialBinding: materialBinding)
        }) else {
            throw ProbeFailure.injected
        }
        return .init(
            context: context,
            conductorContext: conductorContext,
            foreignContext: foreignContext,
            material: material,
            foreignMaterial: foreignMaterial,
            materialBinding: materialBinding,
            componentBatch: batches[0],
            signatureBatch: batches[1]
        )
    }

    private var relayLimits: Nostr.RelayMessageCodingLimits {
        get throws {
            try .init(
                maximumFrameByteCount:
                    Alpha.nip59MaximumPublicationFrameByteCount,
                maximumFiltersPerRequest: 1,
                maximumValuesPerFilter: 1,
                maximumMessageStringByteCount: 256,
                event: (try Transport.codingLimits).event
            )
        }
    }

    private func makePublisher(
        fixture: SharedFixture,
        routeProbe: RouteProviderProbe,
        permitProbe: PermitProbe
    ) throws -> Publisher {
        try .init(
            context: fixture.context,
            material: fixture.material,
            relaySelection: makeRelaySelection(context: fixture.context),
            codingLimits: relayLimits,
            maximumPendingRelayOutputCount: 4,
            provideRoutes: { requests in
                try await routeProbe.provide(requests)
            },
            awaitPublicationPermit: { request in
                try await permitProbe.awaitPermit(request)
            }
        )
    }

    private func routeRequests(
        _ batch: Bridge.GiftWrapBatch
    ) -> [Publisher.RecipientRouteRequest] {
        batch.recipients.map {
            .init(recipientEventIdentity: $0.recipientEventIdentity)
        }.sorted {
            $0.recipientEventIdentity.lexicographicallyPrecedes(
                $1.recipientEventIdentity
            )
        }
    }

    private func makeRouteAllocation(
        batch: Bridge.GiftWrapBatch
    ) -> RouteAllocation {
        var connectionsByIdentity: [
            Data: [ScriptedMosaicTorWebSocketConnection]
        ] = [:]
        let groups = batch.recipients.map { recipient in
            let connections = (0 ..< Alpha.relayCount).map { _ in
                ScriptedMosaicTorWebSocketConnection()
            }
            connectionsByIdentity[recipient.recipientEventIdentity] =
                connections
            return Publisher.RecipientRouteGroup(
                recipientEventIdentity: recipient.recipientEventIdentity,
                routes: zip(selectedEndpoints, connections).map {
                    .init(endpoint: $0.0, connection: $0.1)
                }
            )
        }
        return .init(
            groups: groups,
            connections: connectionsByIdentity
        )
    }

    private func makeRelaySelection(
        context: Bridge.Context,
        digest: [UInt8]? = nil
    ) throws -> Alpha.PostManifestRelaySelectionValidation {
        let effectiveDigest = digest ?? context.manifest.core.relaySetDigest
        return try .init(
            manifestRelaySetDigest: effectiveDigest,
            endpoints: selectedEndpoints,
            using: ExactRelaySelectionValidator(
                expectedDigest: effectiveDigest,
                expectedEndpoints: Set(selectedEndpoints)
            )
        )
    }

    private var selectedEndpoints: [Tracker.Endpoint] {
        (1 ... Alpha.relayCount).map {
            .init(validatedIdentifier: "relay-\($0)")
        }
    }

    private func acknowledgement(
        for giftWrap: Alpha.PostManifestRelayPublisher.GiftWrap,
        accepted: Bool
    ) -> OpalFusion.Mosaic.TorWebSocketMessage {
        let identifier = Nostr.EventCodec.hexadecimal(
            giftWrap.event.identifier.rawRepresentation
        )
        return .text(
            Data(
                ("[\"OK\",\"" + identifier + "\"," + String(accepted)
                    + ",\"relay\"]").utf8
            )
        )
    }

    private func waitForEverySend(
        batch: Bridge.GiftWrapBatch,
        allocation: RouteAllocation
    ) async {
        await withTaskGroup(of: Void.self) { group in
            for recipient in batch.recipients {
                for connection in allocation.connections[
                    recipient.recipientEventIdentity
                ] ?? [] {
                    group.addTask {
                        await connection.waitUntilSentTextCount(1)
                    }
                }
            }
        }
    }

    private func frames(
        from connections: [ScriptedMosaicTorWebSocketConnection]
    ) async -> [String] {
        var result: [String] = []
        for connection in connections {
            if let frame = await connection.sentTexts.first {
                result.append(frame)
            }
        }
        return result
    }

    private func assertNoExposure(
        _ allocation: RouteAllocation
    ) async throws {
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.sentTexts.isEmpty)
            }
        }
    }

    private func assertClosedWithoutExposure(
        _ allocation: RouteAllocation
    ) async throws {
        for connections in allocation.connections.values {
            for connection in connections {
                #expect(await connection.openCount == 0)
                #expect(await connection.closeCount == 1)
                #expect(await connection.sentTexts.isEmpty)
            }
        }
    }
}
