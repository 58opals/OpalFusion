// MosaicMainnetAlphaPostManifestRelayPublisherValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic mainnet-alpha post-manifest relay publication validation")
struct MosaicMainnetAlphaPostManifestRelayPublisherValidator {
    typealias Alpha = OpalFusion.Mosaic.OpalMainnetAlpha
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Publisher = Alpha.PostManifestRelayPublisher
    typealias Transport = Alpha.PostManifestNIP59Transport
    typealias Tracker = OpalFusion.Mosaic.RelayPublicationTracker

    private enum FixtureFailure: Error {
        case rejected
    }

    private struct ExactRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating
    {
        let expectedRelaySetDigest: [UInt8]
        let expectedEndpoints: Set<Tracker.Endpoint>

        func validateRelaySelection(
            manifestRelaySetDigest: [UInt8],
            endpoints: [Tracker.Endpoint]
        ) throws {
            guard manifestRelaySetDigest == expectedRelaySetDigest,
                  Set(endpoints) == expectedEndpoints else {
                throw FixtureFailure.rejected
            }
        }
    }

    private struct RejectingRelaySelectionValidator:
        Alpha.PostManifestRelaySelectionValidating
    {
        func validateRelaySelection(
            manifestRelaySetDigest _: [UInt8],
            endpoints _: [Tracker.Endpoint]
        ) throws {
            throw FixtureFailure.rejected
        }
    }

    private actor CompletionProbe {
        private(set) var isCompleted = false

        func markCompleted() {
            isCompleted = true
        }
    }

    @Test("Require exactly three distinct relay routes and alpha.5 limits")
    func requireExactRoutesAndLimits() async throws {
        let connections = makeConnections()
        #expect(
            throws: Alpha.PostManifestRelaySelectionValidation.ValidationError
                .invalidRelaySetDigest(actual: 31)
        ) {
            _ = try Alpha.PostManifestRelaySelectionValidation(
                manifestRelaySetDigest: Array(relaySetDigest.dropLast()),
                endpoints: selectedEndpoints,
                using: ExactRelaySelectionValidator(
                    expectedRelaySetDigest: relaySetDigest,
                    expectedEndpoints: Set(selectedEndpoints)
                )
            )
        }
        #expect(
            throws: Alpha.PostManifestRelaySelectionValidation.ValidationError
                .invalidRelayCount(actual: 2)
        ) {
            _ = try Alpha.PostManifestRelaySelectionValidation(
                manifestRelaySetDigest: relaySetDigest,
                endpoints: Array(selectedEndpoints.prefix(2)),
                using: RejectingRelaySelectionValidator()
            )
        }
        #expect(
            throws: Alpha.PostManifestRelaySelectionValidation.ValidationError
                .duplicateRelay(endpoint(1))
        ) {
            _ = try Alpha.PostManifestRelaySelectionValidation(
                manifestRelaySetDigest: relaySetDigest,
                endpoints: [endpoint(1), endpoint(2), endpoint(1)],
                using: RejectingRelaySelectionValidator()
            )
        }
        #expect(
            throws: Alpha.PostManifestRelaySelectionValidation.ValidationError.rejected
        ) {
            _ = try Alpha.PostManifestRelaySelectionValidation(
                manifestRelaySetDigest: relaySetDigest,
                endpoints: selectedEndpoints,
                using: RejectingRelaySelectionValidator()
            )
        }
        #expect(
            throws: Publisher.InitializationError.invalidRelayCount(actual: 2)
        ) {
            _ = try makePublisher(
                routes: Array(makeRoutes(connections).prefix(2))
            )
        }
        #expect(
            throws: Publisher.InitializationError.invalidRelayCount(actual: 4)
        ) {
            _ = try makePublisher(
                routes: makeRoutes(connections) + [
                    .init(
                        endpoint: endpoint(4),
                        connection: ScriptedMosaicTorWebSocketConnection()
                    )
                ]
            )
        }
        #expect(
            throws: Publisher.InitializationError.duplicateRelay(endpoint(1))
        ) {
            _ = try makePublisher(
                routes: [
                    .init(endpoint: endpoint(1), connection: connections[0]),
                    .init(endpoint: endpoint(2), connection: connections[1]),
                    .init(endpoint: endpoint(1), connection: connections[2]),
                ]
            )
        }
        #expect(throws: Publisher.InitializationError.duplicateConnection) {
            _ = try makePublisher(
                routes: [
                    .init(endpoint: endpoint(1), connection: connections[0]),
                    .init(endpoint: endpoint(2), connection: connections[0]),
                    .init(endpoint: endpoint(3), connection: connections[2]),
                ]
            )
        }
        #expect(
            throws: Publisher.InitializationError.relaySelectionMismatch
        ) {
            _ = try makePublisher(
                routes: [
                    .init(endpoint: endpoint(1), connection: connections[0]),
                    .init(endpoint: endpoint(2), connection: connections[1]),
                    .init(endpoint: endpoint(4), connection: connections[2]),
                ]
            )
        }
        #expect(
            throws: Publisher.InitializationError.invalidOutputBufferLimit
        ) {
            _ = try Publisher(
                routes: makeRoutes(connections),
                relaySelection: makeRelaySelectionValidation(),
                codingLimits: relayLimits,
                maximumPendingRelayOutputCount: 0
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
                routes: makeRoutes(connections),
                relaySelection: makeRelaySelectionValidation(),
                codingLimits: incompatibleLimits,
                maximumPendingRelayOutputCount: 4
            )
        }

        for connection in connections {
            #expect(await connection.openCount == 0)
        }
    }

    @Test("Reject a signed event outside the frozen gift-wrap shape")
    func rejectForeignSignedEvent() throws {
        let signingKey = try makeSigningKey(7)
        let template = try Nostr.EventTemplate(
            createdAt: 1_700_000_100,
            kind: 1,
            tags: [],
            content: "not-a-gift-wrap",
            limits: (try Transport.codingLimits).event
        )
        let event = try Nostr.EventSigner.sign(
            template,
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0x71, count: 32)
            ),
            limits: (try Transport.codingLimits).event
        )

        #expect(throws: Publisher.Failure.invalidGiftWrap) {
            _ = try Publisher.GiftWrap(validating: event)
        }
    }

    @Test("Require a valid recipient key distinct from the wrapper key")
    func rejectInvalidRecipientKey() throws {
        let validContent = try makeGiftWrap().event.template.content
        let wrapper = try makeSigningKey(21)
        let invalidRecipient = try makeSignedGiftWrap(
            recipientIdentity: String(repeating: "f", count: 64),
            content: validContent,
            wrapper: wrapper
        )
        #expect(throws: Publisher.Failure.invalidGiftWrap) {
            _ = try Publisher.GiftWrap(validating: invalidRecipient)
        }

        let collidingRecipient = try makeSignedGiftWrap(
            recipientIdentity: hexadecimal(
                wrapper.bip340VerificationKey.rawRepresentation
            ),
            content: validContent,
            wrapper: wrapper
        )
        #expect(throws: Publisher.Failure.invalidGiftWrap) {
            _ = try Publisher.GiftWrap(validating: collidingRecipient)
        }
    }

    @Test(
        "Replicate one identical event and accept two relay acknowledgements",
        .timeLimit(.minutes(1))
    )
    func acceptTwoAcknowledgements() async throws {
        let connections = makeConnections()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let publication = Task { try await publisher.publish(giftWrap) }

        for connection in connections {
            await connection.waitUntilSentTextCount(1)
        }
        await connections[0].receive(acknowledgement(for: giftWrap, accepted: true))
        await connections[1].receive(acknowledgement(for: giftWrap, accepted: true))
        try await publication.value

        var frames: [[String]] = []
        for connection in connections {
            frames.append(await connection.sentTexts)
        }
        #expect(frames.allSatisfy { $0.count == 1 })
        #expect(Set(frames.compactMap(\.first)).count == 1)
        #expect(
            await publisher.state == .terminal(.accepted(giftWrap.event.identifier))
        )
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }

        await #expect(throws: Publisher.Failure.alreadyUsed) {
            try await publisher.publish(giftWrap)
        }
    }

    @Test(
        "Do not return before every relay send handoff has completed",
        .timeLimit(.minutes(1))
    )
    func waitForEverySendHandoff() async throws {
        let connections = makeConnections()
        await connections[2].suspendNextSend()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let publication = Task { try await publisher.publish(giftWrap) }

        for connection in connections {
            await connection.waitUntilSentTextCount(1)
        }
        await connections[0].receive(acknowledgement(for: giftWrap, accepted: true))
        await connections[1].receive(acknowledgement(for: giftWrap, accepted: true))

        #expect(await publisher.state == .publishing(giftWrap.event.identifier))
        await connections[2].resumeSend()
        try await publication.value
    }

    @Test(
        "Tolerate one unavailable route after all three were attempted",
        .timeLimit(.minutes(1))
    )
    func tolerateOneUnavailableRoute() async throws {
        let connections = makeConnections()
        await connections[2].failNextOpen()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let publication = Task { try await publisher.publish(giftWrap) }

        await connections[0].waitUntilSentTextCount(1)
        await connections[1].waitUntilSentTextCount(1)
        await connections[0].receive(acknowledgement(for: giftWrap, accepted: true))
        await connections[1].receive(acknowledgement(for: giftWrap, accepted: true))
        try await publication.value

        #expect(await connections[2].openCount == 1)
        #expect(await connections[2].sentTexts.isEmpty)
        #expect(await connections[2].closeCount == 1)
    }

    @Test(
        "Tolerate one relay send failure after the event handoff was attempted",
        .timeLimit(.minutes(1))
    )
    func tolerateOneSendFailure() async throws {
        let connections = makeConnections()
        await connections[2].failNextSend()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let publication = Task { try await publisher.publish(giftWrap) }

        for connection in connections {
            await connection.waitUntilSentTextCount(1)
        }
        await connections[0].receive(acknowledgement(for: giftWrap, accepted: true))
        await connections[1].receive(acknowledgement(for: giftWrap, accepted: true))
        try await publication.value

        #expect(await connections[2].sentTexts.count == 1)
        #expect(await connections[2].closeCount == 1)
    }

    @Test(
        "Preserve an accepted ACK when that route later closes a suspended send",
        .timeLimit(.minutes(1))
    )
    func preferAcknowledgementOverLaterSendFailure() async throws {
        let connections = makeConnections()
        await connections[0].suspendNextSend()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let publication = Task { try await publisher.publish(giftWrap) }

        for connection in connections {
            await connection.waitUntilSentTextCount(1)
        }
        await connections[0].receive(
            acknowledgement(for: giftWrap, accepted: true)
        )
        await connections[0].receive(
            acknowledgement(for: giftWrap, accepted: true)
        )
        await connections[0].waitUntilClosed()
        await connections[1].receive(
            acknowledgement(for: giftWrap, accepted: true)
        )
        await connections[2].receive(
            acknowledgement(for: giftWrap, accepted: false)
        )

        try await publication.value
        #expect(
            await publisher.state
                == .terminal(.accepted(giftWrap.event.identifier))
        )
    }

    @Test(
        "Fail once two accepted acknowledgements become impossible",
        .timeLimit(.minutes(1))
    )
    func failImpossibleQuorum() async throws {
        let connections = makeConnections()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let publication = Task { try await publisher.publish(giftWrap) }

        for connection in connections {
            await connection.waitUntilSentTextCount(1)
        }
        await connections[0].receive(acknowledgement(for: giftWrap, accepted: true))
        await connections[1].receive(acknowledgement(for: giftWrap, accepted: false))
        await connections[2].receive(acknowledgement(for: giftWrap, accepted: false))

        await #expect(throws: Publisher.Failure.publicationRejected) {
            try await publication.value
        }
        #expect(
            await publisher.state
                == .terminal(.failed(.publicationRejected))
        )
    }

    @Test(
        "Cancellation awaits a blocked close while unblocking a suspended open",
        .timeLimit(.minutes(1))
    )
    func cancelPendingPublication() async throws {
        let connections = makeConnections()
        await connections[2].suspendNextOpen()
        await connections[0].suspendNextClose()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let completion = CompletionProbe()
        let publication = Task {
            do {
                try await publisher.publish(giftWrap)
                await completion.markCompleted()
            } catch {
                await completion.markCompleted()
                throw error
            }
        }

        await connections[2].waitUntilOpenSuspends()
        publication.cancel()
        await connections[0].waitUntilCloseSuspends()

        #expect(await publisher.state == .stopping)
        #expect(await completion.isCompleted == false)
        await connections[0].resumeClose()

        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        #expect(await publisher.state == .terminal(.stopped))
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Explicit stop drains a blocked close before publication returns",
        .timeLimit(.minutes(1))
    )
    func stopPendingPublication() async throws {
        let connections = makeConnections()
        await connections[2].suspendNextOpen()
        await connections[0].suspendNextClose()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let completion = CompletionProbe()
        let publication = Task {
            do {
                try await publisher.publish(giftWrap)
                await completion.markCompleted()
            } catch {
                await completion.markCompleted()
                throw error
            }
        }

        await connections[2].waitUntilOpenSuspends()
        let observeBlockedClose = Task {
            await connections[0].waitUntilCloseSuspends()
            #expect(await publisher.state == .stopping)
            #expect(await completion.isCompleted == false)
            await connections[0].resumeClose()
        }
        await publisher.stop()
        await observeBlockedClose.value

        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        #expect(await publisher.state == .terminal(.stopped))
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    @Test(
        "Direct stop joins response cleanup already blocked in close",
        .timeLimit(.minutes(1))
    )
    func stopDuringResponseCleanup() async throws {
        let connections = makeConnections()
        await connections[0].suspendNextClose()
        let publisher = try makePublisher(routes: makeRoutes(connections))
        let giftWrap = try makeGiftWrap()
        let publicationCompletion = CompletionProbe()
        let stopCompletion = CompletionProbe()
        let publication = Task {
            do {
                try await publisher.publish(giftWrap)
                await publicationCompletion.markCompleted()
            } catch {
                await publicationCompletion.markCompleted()
                throw error
            }
        }

        for connection in connections {
            await connection.waitUntilSentTextCount(1)
        }
        await connections[0].receive(
            acknowledgement(for: giftWrap, accepted: true)
        )
        await connections[1].receive(
            acknowledgement(for: giftWrap, accepted: true)
        )
        await connections[0].waitUntilCloseSuspends()

        let observeStop = Task {
            while await publisher.state
                    == .publishing(giftWrap.event.identifier) {
                await Task.yield()
            }
            #expect(await publisher.state == .stopping)
            #expect(await stopCompletion.isCompleted == false)
            #expect(await publicationCompletion.isCompleted == false)
            await connections[0].resumeClose()
        }
        await publisher.stop()
        await stopCompletion.markCompleted()
        await observeStop.value

        await #expect(throws: Publisher.Failure.cancelled) {
            try await publication.value
        }
        #expect(await publisher.state == .terminal(.stopped))
        for connection in connections {
            #expect(await connection.closeCount == 1)
        }
    }

    private var relayLimits: Nostr.RelayMessageCodingLimits {
        get throws {
            try .init(
                maximumFrameByteCount: Alpha.nip59MaximumPublicationFrameByteCount,
                maximumFiltersPerRequest: 1,
                maximumValuesPerFilter: 1,
                maximumMessageStringByteCount: 256,
                event: (try Transport.codingLimits).event
            )
        }
    }

    private func makePublisher(
        routes: [Alpha.PostManifestRelayRoute]
    ) throws -> Publisher {
        try .init(
            routes: routes,
            relaySelection: makeRelaySelectionValidation(),
            codingLimits: relayLimits,
            maximumPendingRelayOutputCount: 4
        )
    }

    private var relaySetDigest: [UInt8] {
        [UInt8](repeating: 0x44, count: 32)
    }

    private var selectedEndpoints: [Tracker.Endpoint] {
        (1 ... Alpha.relayCount).map(endpoint)
    }

    private func makeRelaySelectionValidation() throws
        -> Alpha.PostManifestRelaySelectionValidation
    {
        try .init(
            manifestRelaySetDigest: relaySetDigest,
            endpoints: selectedEndpoints,
            using: ExactRelaySelectionValidator(
                expectedRelaySetDigest: relaySetDigest,
                expectedEndpoints: Set(selectedEndpoints)
            )
        )
    }

    private func makeConnections() -> [ScriptedMosaicTorWebSocketConnection] {
        (0 ..< Alpha.relayCount).map { _ in
            ScriptedMosaicTorWebSocketConnection()
        }
    }

    private func makeRoutes(
        _ connections: [ScriptedMosaicTorWebSocketConnection]
    ) -> [Alpha.PostManifestRelayRoute] {
        zip(1..., connections).map {
            .init(endpoint: endpoint($0.0), connection: $0.1)
        }
    }

    private func endpoint(_ index: Int) -> Tracker.Endpoint {
        .init(validatedIdentifier: "relay-\(index)")
    }

    private func makeGiftWrap() throws -> Publisher.GiftWrap {
        let sender = try makeSigningKey(11)
        let recipient = try makeSigningKey(12)
        let limits = try Transport.codingLimits
        let content = try OpalFusion.Mosaic.PaddedEnvelopeCodec.encode([0x01])
        let rumorTemplate = try Nostr.EventTemplate(
            createdAt: 1_700_000_100,
            kind: Alpha.nip59RumorKind,
            tags: [[
                "d",
                OpalFusion.Mosaic.TransportProfile
                    .nostrTorOpalMainnetAlpha.rawValue,
            ]],
            content: content,
            limits: limits.event
        )
        let rumor = try Nostr.UnsignedEvent(
            publicKey: sender.bip340VerificationKey,
            template: rumorTemplate,
            limits: limits.event
        )
        let seal = try Nostr.NIP59EnvelopeCodec.seal(
            rumor,
            createdAt: 1_700_000_090,
            senderSigningKey: sender,
            recipientPublicKey: recipient.bip340VerificationKey,
            limits: limits
        )
        let event = try Nostr.NIP59EnvelopeCodec.wrap(
            seal,
            deliveryKind: .regular,
            createdAt: 1_700_000_091,
            limits: limits
        )
        return try .init(validating: event)
    }

    private func makeSigningKey(
        _ value: UInt8
    ) throws -> OpalCrypto.Secp256k1.SigningKey {
        try .init(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([value])
        )
    }

    private func makeSignedGiftWrap(
        recipientIdentity: String,
        content: String,
        wrapper: OpalCrypto.Secp256k1.SigningKey
    ) throws -> Nostr.Event {
        let template = try Nostr.EventTemplate(
            createdAt: 1_700_000_091,
            kind: Nostr.NIP59EnvelopeCodec.DeliveryKind.regular.rawValue,
            tags: [["p", recipientIdentity]],
            content: content,
            limits: (try Transport.codingLimits).event
        )
        return try Nostr.EventSigner.sign(
            template,
            using: wrapper,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0x72, count: 32)
            ),
            limits: (try Transport.codingLimits).event
        )
    }

    private func acknowledgement(
        for giftWrap: Publisher.GiftWrap,
        accepted: Bool
    ) -> OpalFusion.Mosaic.TorWebSocketMessage {
        let identifier = hexadecimal(giftWrap.event.identifier.rawRepresentation)
        return .text(
            Data(
                ("[\"OK\",\"" + identifier + "\"," + String(accepted)
                    + ",\"relay\"]").utf8
            )
        )
    }

    private func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
