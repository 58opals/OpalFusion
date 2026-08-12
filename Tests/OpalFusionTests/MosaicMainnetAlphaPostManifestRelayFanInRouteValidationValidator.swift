// MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest relay fan-in route validation")
struct MosaicMainnetAlphaPostManifestRelayFanInRouteValidationValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias FanIn = Alpha.PostManifestRelayFanIn
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker
    typealias Transport = Alpha.PostManifestNIP59Transport

    private struct ExactRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating {
        let digest: [UInt8]
        let endpoints: Set<Tracker.Endpoint>

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [Tracker.Endpoint]
        ) throws {
            guard manifestRelaySetDigest == digest,
                  Set(endpoints) == self.endpoints else {
                throw ProbeFailure.unexpectedInvocation
            }
        }
    }

    @Test("Accept one contributor control group without touching a route")
    func acceptContributorPlanWithoutEffects() async throws {
        let connections = makeConnections()
        let subscriptions = try makeSubscriptions()
        let group = try routeGroup(
            recipientScalar: 21,
            channel: .control,
            connections: connections,
            subscriptions: subscriptions
        )

        try FanIn.validateRoutePlan(
            role: .contributor,
            maximumAnonymousRecipientCount: 0,
            manifestRelaySetDigest: digest,
            recipientRouteGroups: [group],
            relaySelection: try relaySelection(),
            codingLimits: try codingLimits(subscriptions.values),
            maximumPendingEventCount: 1
        )

        for connection in connections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 0)
        }
    }

    @Test("Reject malformed collection shape before touching a route")
    func rejectMalformedCollectionShape() async throws {
        let controlConnections = makeConnections()
        let anonymousConnections = makeConnections()
        let controlSubscriptions = try makeSubscriptions(prefix: "control")
        let anonymousSubscriptions = try makeSubscriptions(prefix: "anonymous")
        let control = try routeGroup(
            recipientScalar: 21,
            channel: .control,
            connections: controlConnections,
            subscriptions: controlSubscriptions
        )
        let anonymous = try routeGroup(
            recipientScalar: 22,
            channel: .anonymous,
            connections: anonymousConnections,
            subscriptions: anonymousSubscriptions
        )
        let limits = try codingLimits(
            Array(controlSubscriptions.values)
                + Array(anonymousSubscriptions.values)
        )

        #expect(
            throws: FanIn.InitializationError
                .invalidRecipientGroupCount(actual: 0)
        ) {
            try validate([], role: .conductor, codingLimits: limits)
        }
        #expect(throws: FanIn.InitializationError.invalidRecipientChannels) {
            try validate([anonymous], role: .contributor, codingLimits: limits)
        }
        #expect(throws: FanIn.InitializationError.invalidRecipientSet) {
            try validate([control, control], role: .conductor, codingLimits: limits)
        }
        let reusedConnection = try routeGroup(
            recipientScalar: 22,
            channel: .anonymous,
            connections: [
                controlConnections[0],
                anonymousConnections[1],
                anonymousConnections[2],
            ],
            subscriptions: anonymousSubscriptions
        )
        #expect(throws: FanIn.InitializationError.duplicateConnection) {
            try validate(
                [control, reusedConnection],
                role: .conductor,
                codingLimits: limits
            )
        }
        var reusedSubscriptions = anonymousSubscriptions
        reusedSubscriptions[endpoints[0]] = controlSubscriptions[endpoints[0]]
        let duplicateSubscription = try routeGroup(
            recipientScalar: 22,
            channel: .anonymous,
            connections: anonymousConnections,
            subscriptions: reusedSubscriptions
        )
        #expect(
            throws: FanIn.InitializationError.duplicateSubscriptionIdentifier
        ) {
            try validate(
                [control, duplicateSubscription],
                role: .conductor,
                codingLimits: limits
            )
        }

        for connection in controlConnections + anonymousConnections {
            #expect(await connection.openCount == 0)
            #expect(await connection.closeCount == 0)
        }
    }

    @Test("Reject incompatible relay and buffer contracts without effects")
    func rejectIncompatibleContracts() throws {
        let subscriptions = try makeSubscriptions()
        let group = try routeGroup(
            recipientScalar: 21,
            channel: .control,
            connections: makeConnections(),
            subscriptions: subscriptions
        )
        let limits = try codingLimits(subscriptions.values)

        #expect(throws: FanIn.InitializationError.invalidEventBufferLimit) {
            try FanIn.validateRoutePlan(
                role: .contributor,
                maximumAnonymousRecipientCount: 0,
                manifestRelaySetDigest: digest,
                recipientRouteGroups: [group],
                relaySelection: try relaySelection(),
                codingLimits: limits,
                maximumPendingEventCount: 0
            )
        }
        #expect(
            throws: FanIn.InitializationError.relaySelectionManifestMismatch
        ) {
            try FanIn.validateRoutePlan(
                role: .contributor,
                maximumAnonymousRecipientCount: 0,
                manifestRelaySetDigest: [UInt8](repeating: 0x44, count: 32),
                recipientRouteGroups: [group],
                relaySelection: try relaySelection(),
                codingLimits: limits,
                maximumPendingEventCount: 1
            )
        }
        let shortGroup = try routeGroup(
            recipientScalar: 21,
            channel: .control,
            connections: Array(makeConnections().prefix(2)),
            subscriptions: subscriptions
        )
        #expect(
            throws: FanIn.InitializationError.invalidRelayCount(actual: 2)
        ) {
            try validate([shortGroup], role: .contributor, codingLimits: limits)
        }
    }

    private func validate(
        _ groups: [FanIn.RecipientRouteGroup],
        role: OpalFusion.Mosaic.Role,
        codingLimits: Nostr.RelayMessageCodingLimits
    ) throws {
        try FanIn.validateRoutePlan(
            role: role,
            maximumAnonymousRecipientCount: 2,
            manifestRelaySetDigest: digest,
            recipientRouteGroups: groups,
            relaySelection: try relaySelection(),
            codingLimits: codingLimits,
            maximumPendingEventCount: 1
        )
    }

    private func routeGroup(
        recipientScalar: UInt8,
        channel: Transport.Channel,
        connections: [any OpalFusion.Mosaic.TorWebSocketConnectioning],
        subscriptions: [Tracker.Endpoint: Nostr.SubscriptionIdentifier]
    ) throws -> FanIn.RecipientRouteGroup {
        .init(
            recipient: .init(
                channel: channel,
                signingKey: try signingKey(recipientScalar)
            ),
            routes: zip(endpoints, connections).map {
                .init(endpoint: $0.0, connection: $0.1)
            },
            subscriptionIdentifiers: subscriptions
        )
    }

    private func relaySelection() throws
        -> Alpha.PostManifestRelaySelectionValidation {
        try .init(
            manifestRelaySetDigest: digest,
            endpoints: endpoints,
            using: ExactRelaySelectionValidator(
                digest: digest,
                endpoints: Set(endpoints)
            )
        )
    }

    private func codingLimits<S: Sequence>(
        _ subscriptions: S
    ) throws -> Nostr.RelayMessageCodingLimits
    where S.Element == Nostr.SubscriptionIdentifier {
        let identifierWidth = try subscriptions.map {
            try JSONEncoder().encode($0.value).count
        }.max() ?? 0
        let maximumFrameByteCount = Data("[\"EVENT\",".utf8).count
            + identifierWidth + 1
            + Alpha.nip59MaximumGiftWrapJSONByteCount + 1
        return try .init(
            maximumFrameByteCount: maximumFrameByteCount,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 256,
            event: (try Transport.codingLimits).event
        )
    }

    private func makeSubscriptions(
        prefix: String = "route"
    ) throws -> [Tracker.Endpoint: Nostr.SubscriptionIdentifier] {
        try Dictionary(
            uniqueKeysWithValues: endpoints.enumerated().map {
                ($0.element, try .init("\(prefix)-\($0.offset)"))
            }
        )
    }

    private func makeConnections() -> [ScriptedMosaicTorWebSocketConnection] {
        (0 ..< Alpha.relayCount).map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
    }

    private func signingKey(
        _ scalarByte: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalarByte])
        )
    }

    private var digest: [UInt8] { [UInt8](repeating: 0xA5, count: 32) }

    private var endpoints: [Tracker.Endpoint] {
        (1 ... Alpha.relayCount).map {
            Tracker.Endpoint(validatedIdentifier: "route-validation-\($0)")
        }
    }

    private enum ProbeFailure: Error {
        case unexpectedInvocation
    }
}
