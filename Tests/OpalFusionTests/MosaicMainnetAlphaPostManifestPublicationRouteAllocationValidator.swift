// MosaicMainnetAlphaPostManifestPublicationRouteAllocationValidator.swift

import Foundation
import Testing

@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest publication route allocation")
struct MosaicMainnetAlphaPostManifestPublicationRouteAllocationValidator {
    private typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    private typealias Allocation = Alpha.PostManifestPublicationRouteAllocation
    private typealias Closer = Alpha.PostManifestPublicationRouteCloser
    private typealias Route = Alpha.PostManifestRelayRoute

    private enum GroupMismatch: CaseIterable, Sendable {
        case missing
        case foreign
        case duplicate
    }

    private enum ConnectionReuse: CaseIterable, Sendable {
        case withinGroup
        case acrossGroups
    }

    private actor CompletionProbe {
        private(set) var isCompleted = false

        func complete() {
            isCompleted = true
        }
    }

    private actor InvocationCountingConnection:
        OpalFusion.Mosaic.TorWebSocketConnectioning
    {
        private(set) var closeInvocationCount = 0

        func open(
            maximumIncomingMessageByteCount _: Int
        ) async throws -> MessageStream {
            let (stream, continuation) = MessageStream.makeStream()
            continuation.finish()
            return stream
        }

        func send(text _: String) async throws {}

        func close() async {
            closeInvocationCount += 1
        }
    }

    @Test("Sort route requests by recipient event identity")
    func sortRequests() {
        let identities = [Data([0x30]), Data([0x10]), Data([0x20])]

        let requests = Allocation.requests(for: identities)

        #expect(
            requests.map(\.recipientEventIdentity)
                == [Data([0x10]), Data([0x20]), Data([0x30])]
        )
    }

    @Test("Index a reversed complete allocation by recipient identity")
    func indexReversedCompleteAllocation() throws {
        let identities = [Data([0x10]), Data([0x20]), Data([0x30])]
        let connections = identities.map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
        let groups = zip(identities, connections).enumerated().map {
            index, pair in
            Allocation.RecipientRouteGroup(
                recipientEventIdentity: pair.0,
                routes: [makeRoute(index: index, connection: pair.1)]
            )
        }

        let allocation = try Allocation(
            expectedRecipientEventIdentities: identities,
            routeGroups: Array(groups.reversed())
        )

        for (identity, connection) in zip(identities, connections) {
            let routes = try #require(allocation.routes(for: identity))
            #expect(routes.count == 1)
            #expect(
                connectionIdentity(of: routes[0])
                    == ObjectIdentifier(connection)
            )
        }
        #expect(allocation.routes(for: Data([0xff])) == nil)
    }

    @Test(
        "Reject an incomplete, foreign, or duplicate recipient group",
        arguments: GroupMismatch.allCases
    )
    private func rejectGroupMismatch(_ mismatch: GroupMismatch) {
        let identities = [Data([0x10]), Data([0x20])]
        let firstConnection = ScriptedMosaicTorWebSocketConnection()
        let secondConnection = ScriptedMosaicTorWebSocketConnection()
        let first = Allocation.RecipientRouteGroup(
            recipientEventIdentity: identities[0],
            routes: [makeRoute(index: 0, connection: firstConnection)]
        )
        let groups: [Allocation.RecipientRouteGroup]
        switch mismatch {
        case .missing:
            groups = [first]
        case .foreign:
            groups = [
                first,
                .init(
                    recipientEventIdentity: Data([0xff]),
                    routes: [makeRoute(index: 1, connection: secondConnection)]
                ),
            ]
        case .duplicate:
            groups = [first, first]
        }

        #expect(
            throws: Allocation.ValidationError.routeAllocationMismatch
        ) {
            _ = try Allocation(
                expectedRecipientEventIdentities: identities,
                routeGroups: groups
            )
        }
    }

    @Test(
        "Reject one connection reused within or across recipient groups",
        arguments: ConnectionReuse.allCases
    )
    private func rejectConnectionReuse(_ reuse: ConnectionReuse) {
        let identities = [Data([0x10]), Data([0x20])]
        let reusedConnection = ScriptedMosaicTorWebSocketConnection()
        let firstRoutes: [Route]
        let secondRoutes: [Route]
        switch reuse {
        case .withinGroup:
            firstRoutes = [
                makeRoute(index: 0, connection: reusedConnection),
                makeRoute(index: 1, connection: reusedConnection),
            ]
            secondRoutes = [
                makeRoute(
                    index: 2,
                    connection: ScriptedMosaicTorWebSocketConnection()
                ),
            ]
        case .acrossGroups:
            firstRoutes = [makeRoute(index: 0, connection: reusedConnection)]
            secondRoutes = [makeRoute(index: 1, connection: reusedConnection)]
        }
        let groups = [
            Allocation.RecipientRouteGroup(
                recipientEventIdentity: identities[0],
                routes: firstRoutes
            ),
            Allocation.RecipientRouteGroup(
                recipientEventIdentity: identities[1],
                routes: secondRoutes
            ),
        ]

        #expect(throws: Allocation.ValidationError.duplicateConnection) {
            _ = try Allocation(
                expectedRecipientEventIdentities: identities,
                routeGroups: groups
            )
        }
    }

    @Test("Close each reused connection exactly once")
    func deduplicateConnectionsWhenClosing() async {
        let first = InvocationCountingConnection()
        let second = InvocationCountingConnection()
        let routes = [
            makeRoute(index: 0, connection: first),
            makeRoute(index: 1, connection: first),
            makeRoute(index: 2, connection: second),
            makeRoute(index: 3, connection: second),
        ]

        await Closer.close(routes)

        #expect(await first.closeInvocationCount == 1)
        #expect(await second.closeInvocationCount == 1)
    }

    @Test("Await every deduplicated connection close")
    func awaitSuspendedClose() async {
        let suspended = ScriptedMosaicTorWebSocketConnection()
        let sibling = ScriptedMosaicTorWebSocketConnection()
        await suspended.suspendNextClose()
        let completion = CompletionProbe()
        let routes = [
            makeRoute(index: 0, connection: suspended),
            makeRoute(index: 1, connection: suspended),
            makeRoute(index: 2, connection: sibling),
        ]

        let closing = Task {
            await Closer.close(routes)
            await completion.complete()
        }
        await suspended.waitUntilCloseSuspends()

        #expect(await completion.isCompleted == false)
        await suspended.resumeClose()
        await closing.value
        #expect(await completion.isCompleted)
        #expect(await suspended.closeCount == 1)
        #expect(await sibling.closeCount == 1)
    }

    private func makeRoute<Connection: OpalFusion.Mosaic.TorWebSocketConnectioning>(
        index: Int,
        connection: Connection
    ) -> Route {
        Route(
            endpoint: .init(
                validatedIdentifier: "allocation-relay-\(index)"
            ),
            connection: connection
        )
    }

    private func connectionIdentity(of route: Route) -> ObjectIdentifier {
        route.connectionIdentity
    }
}
