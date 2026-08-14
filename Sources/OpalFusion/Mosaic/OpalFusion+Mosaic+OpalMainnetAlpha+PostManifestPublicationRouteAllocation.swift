// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestPublicationRouteAllocation.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha {
    /// One complete recipient-keyed outbound route allocation.
    struct PostManifestPublicationRouteAllocation: Sendable {
        struct RecipientRouteRequest: Sendable, Equatable {
            let recipientEventIdentity: Data
        }

        struct RecipientRouteGroup: Sendable {
            let recipientEventIdentity: Data
            let routes: [PostManifestRelayRoute]

            init(
                recipientEventIdentity: Data,
                routes: [PostManifestRelayRoute]
            ) {
                self.recipientEventIdentity = recipientEventIdentity
                self.routes = routes
            }
        }

        enum ValidationError: Error, Sendable, Equatable {
            case routeAllocationMismatch
            case duplicateConnection
        }

        private let routesByEventIdentity: [Data: [PostManifestRelayRoute]]

        static func requests(
            for recipientEventIdentities: [Data]
        ) -> [RecipientRouteRequest] {
            recipientEventIdentities
                .map(RecipientRouteRequest.init(recipientEventIdentity:))
                .sorted {
                    $0.recipientEventIdentity.lexicographicallyPrecedes(
                        $1.recipientEventIdentity
                    )
                }
        }

        init(
            expectedRecipientEventIdentities: [Data],
            routeGroups: [RecipientRouteGroup]
        ) throws(ValidationError) {
            let expectedIdentities = Set(expectedRecipientEventIdentities)
            guard expectedIdentities.count
                    == expectedRecipientEventIdentities.count,
                  routeGroups.count
                    == expectedRecipientEventIdentities.count else {
                throw .routeAllocationMismatch
            }

            var routesByEventIdentity: [Data: [PostManifestRelayRoute]] = [:]
            var connectionIdentities: Set<ObjectIdentifier> = []
            for group in routeGroups {
                guard routesByEventIdentity.updateValue(
                    group.routes,
                    forKey: group.recipientEventIdentity
                ) == nil else {
                    throw .routeAllocationMismatch
                }
                for route in group.routes {
                    guard connectionIdentities.insert(
                        ObjectIdentifier(route.connection as AnyObject)
                    ).inserted else {
                        throw .duplicateConnection
                    }
                }
            }
            guard Set(routesByEventIdentity.keys) == expectedIdentities else {
                throw .routeAllocationMismatch
            }
            self.routesByEventIdentity = routesByEventIdentity
        }

        func routes(
            for recipientEventIdentity: Data
        ) -> [PostManifestRelayRoute]? {
            routesByEventIdentity[recipientEventIdentity]
        }
    }

    /// Closes every distinct connection in a returned raw route allocation.
    struct PostManifestPublicationRouteCloser: Sendable {
        static func close(_ routes: [PostManifestRelayRoute]) async {
            await withTaskGroup(of: Void.self) { group in
                var connectionIdentities: Set<ObjectIdentifier> = []
                for route in routes {
                    guard connectionIdentities.insert(
                        ObjectIdentifier(route.connection as AnyObject)
                    ).inserted else {
                        continue
                    }
                    group.addTask {
                        await route.connection.close()
                    }
                }
            }
        }
    }
}
