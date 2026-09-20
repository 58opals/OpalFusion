// MosaicPrivateDeploymentInboxValidator.swift

import Foundation
import OpalCrypto
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalFusion

@Suite("Mosaic private deployment inbox")
struct MosaicPrivateDeploymentInboxValidator {
    private typealias Runtime = OpalFusion.MosaicPrivateAlphaRuntime
    private typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha

    @Test("Three relay copies yield one canonical event with local receipt time")
    func fanInAndLoss() async throws {
        let (inbox, connections) = try makeInbox()
        let stream = try await inbox.start()
        let bytes = try beacon(0)
        for connection in connections { try await deliver(bytes, to: connection) }
        var iterator = stream.makeAsyncIterator()
        let value = try #require(try await iterator.next())
        #expect(value.payloadKind == 0)
        #expect(value.event.canonicalEventBytes == bytes)
        #expect(value.event.acceptedAtUnixSeconds == 1_800_000_002)
        await connections[0].close()
        var duplicates = 0
        await #expect(throws: Runtime.PrivateDeploymentInbox.InboxFailure.sourceLost) {
            while try await iterator.next() != nil { duplicates += 1 }
        }
        #expect(duplicates == 0)
        await inbox.stop()
        for connection in connections { #expect(await connection.closeCount == 1) }
    }

    @Test("More distinct formation events than the bounded limit terminalizes all routes")
    func eventBound() async throws {
        let (inbox, connections) = try makeInbox(maximum: 1)
        let stream = try await inbox.start()
        var iterator = stream.makeAsyncIterator()
        try await deliver(beacon(0), to: connections[0])
        #expect(try await iterator.next() != nil)
        try await deliver(beacon(1), to: connections[0])
        await #expect(throws: Runtime.PrivateDeploymentInbox.InboxFailure.boundedBufferExceeded) {
            _ = try await iterator.next()
        }
        await inbox.stop()
    }

    @Test("Cancelling a consumer after receipt joins all discovery routes", .timeLimit(.minutes(1)))
    func cancelAfterReceipt() async throws {
        let (inbox, connections) = try makeInbox()
        let stream = try await inbox.start()
        let (receipts, receipt) = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingOldest(1))
        let consumer = Task {
            for try await _ in stream { receipt.yield(()) }
        }
        try await deliver(beacon(0), to: connections[0])
        var received = receipts.makeAsyncIterator()
        _ = await received.next()
        consumer.cancel()
        await inbox.stop()
        _ = await consumer.result
        receipt.finish()
        for connection in connections { #expect(await connection.closeCount == 1) }
    }

    @Test("Shared route isolation is rejected before socket startup")
    func rejectsRouteReuse() async throws {
        let (inbox, connections) = try makeInbox(sharedIsolation: UUID())
        await #expect(throws: Runtime.PrivateDeploymentInbox.InboxFailure.invalidRouteAllocation) {
            _ = try await inbox.start()
        }
        for connection in connections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }
    }

    @Test("Stopping before startup and repeated startup never reopen routes")
    func stopAndRestart() async throws {
        let (inbox, connections) = try makeInbox()
        await inbox.stop()
        await #expect(throws: Runtime.PrivateDeploymentInbox.InboxFailure.invalidConfiguration) {
            _ = try await inbox.start()
        }
        for connection in connections { #expect(await connection.openCount == 0) }
        let (running, opened) = try makeInbox()
        _ = try await running.start()
        await #expect(throws: Runtime.PrivateDeploymentInbox.InboxFailure.invalidConfiguration) {
            _ = try await running.start()
        }
        await running.stop()
        for connection in opened { #expect(await connection.closeCount == 1) }
    }

    @Test("Cancellation while provisioning closes all returned routes without opening")
    func cancellationDuringProvisioning() async throws {
        let suspension = MosaicRuntimeCoordinatorSuspensionProbe()
        await suspension.arm()
        let (inbox, connections) = try makeInbox(suspension: suspension)
        let task = Task { try await inbox.start() }
        await suspension.waitUntilSuspended()
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
        for connection in connections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 1)
        }
    }

    private func makeInbox(maximum: Int = 32, sharedIsolation: UUID? = nil,
                           suspension: MosaicRuntimeCoordinatorSuspensionProbe? = nil) throws
        -> (Runtime.PrivateDeploymentInbox, [ScriptedMosaicPrivateAlphaTorConnection]) {
        let preparation = try Runtime.DiscoveryPreparation(
            epochStartUnixSeconds: 1_800_000_000,
            appGeneratedOpaquePoolIdentifier: Data(repeating: 0x31, count: 32),
            relays: (1 ... 3).map { .init(endpoint: "wss://relay-\($0).example/", reviewedOperatorLabel: "fixture operator \($0)") })
        let connections = (0 ..< 3).map { _ in ScriptedMosaicPrivateAlphaTorConnection() }
        let routes = zip(preparation.relayEndpointIdentifiers, connections).map {
            Runtime.PostManifestProvisionedRoute(relayEndpointIdentifier: $0, connection: $1,
                                                isolationIdentifier: sharedIsolation ?? UUID())
        }
        return (try .init(preparation: preparation,
                          binding: .init(attemptIdentifier: Data(repeating: 1, count: 32),
                                         generationIdentifier: Data(repeating: 2, count: 32),
                                         materialIdentifier: Data(repeating: 3, count: 32)),
                          capabilities: .init(provisionRoutes: { _ in
                              await suspension?.suspendIfArmed()
                              return routes
                          }), maximumEventCount: maximum, currentUnixSeconds: { 1_800_000_002 }), connections)
    }

    private func beacon(_ index: Int) throws -> Data {
        let fixture = try MosaicPrivateDeploymentFixtures.makeDiscovery(candidateCount: 7)
        let zero = try OpalCrypto.Signature.BIP340.AuxiliaryRandomness(rawRepresentation: Data(repeating: 0, count: 32))
        return try Runtime.PrivateDeploymentEvent.makeLocal(
            payload: Alpha.PreManifestNostrPayloadDocument.makeAvailabilityBeacon(fixture.beacons[index]),
            createdAtUnixSeconds: 1_800_000_001,
            signing: .init(signingKey: fixture.candidates[index].signingKey,
                           documentAuxiliaryRandomness: zero, eventAuxiliaryRandomness: zero)).canonicalEventBytes
    }

    private func deliver(_ bytes: Data, to connection: ScriptedMosaicPrivateAlphaTorConnection) async throws {
        let request = try #require(await connection.sentTexts.first)
        let frame = try #require(JSONSerialization.jsonObject(with: Data(request.utf8)) as? [Any])
        let subscription = try #require(frame[1] as? String)
        await connection.receive(.text(Data("[\"EVENT\",\"\(subscription)\",\(String(decoding: bytes, as: UTF8.self))]".utf8)))
    }
}
