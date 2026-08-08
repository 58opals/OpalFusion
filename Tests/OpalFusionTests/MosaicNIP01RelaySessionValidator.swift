// MosaicNIP01RelaySessionValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalFusion

@Suite("Mosaic NIP-01 relay session validation")
struct MosaicNIP01RelaySessionValidator {
    typealias Nostr = OpalFusion.Mosaic.NostrNamespace
    typealias Session = OpalFusion.Mosaic.NIP01RelaySession

    enum OutboundOperation: CaseIterable, Sendable, Equatable {
        case subscribe
        case closeSubscription
        case publish
    }

    @Test("Reject invalid output buffering before opening the connection")
    func rejectInvalidOutputBuffer() throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        #expect(throws: Session.Failure.invalidOutputBufferLimit) {
            _ = try Session(
                connection: connection,
                codingLimits: limits,
                maximumPendingOutputCount: 0
            )
        }
    }

    @Test("Start waits for a bounded connection to open", .timeLimit(.minutes(1)))
    func waitForConnectionOpen() async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        await connection.suspendNextOpen()
        let session = try makeSession(connection: connection)
        let expectedMaximumFrameByteCount = (try limits).maximumFrameByteCount
        let event = try makeEvent()
        let subscription = try Nostr.RelaySubscription(
            identifier: .init("opening"),
            filters: [try .init(kinds: [event.template.kind])]
        )

        let starting = Task { try await session.start() }
        await connection.waitUntilOpenSuspends()

        #expect(await session.state == .opening)
        await #expect(throws: Session.Failure.notRunning) {
            try await session.subscribe(subscription)
        }
        #expect(await connection.sentTexts.isEmpty)

        await connection.resumeOpen()
        _ = try await starting.value
        try await session.subscribe(subscription)

        #expect(
            await connection.openedMaximumIncomingMessageByteCount
                == expectedMaximumFrameByteCount
        )
        #expect(await connection.sentTexts.count == 1)
        await session.stop()

        let interruptedConnection = ScriptedMosaicTorWebSocketConnection()
        await interruptedConnection.suspendNextOpen()
        let interruptedSession = try makeSession(connection: interruptedConnection)
        let interruptedStart = Task { try await interruptedSession.start() }
        await interruptedConnection.waitUntilOpenSuspends()

        await interruptedSession.stop()

        await #expect(throws: Session.Failure.notRunning) {
            _ = try await interruptedStart.value
        }
        #expect(await interruptedConnection.closeCount == 1)
    }

    @Test("Correlate subscribed events and close exactly once", .timeLimit(.minutes(1)))
    func correlateSubscription() async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        let session = try makeSession(connection: connection)
        let output = try await session.start()
        var iterator = output.makeAsyncIterator()
        await connection.waitUntilOpened()
        let event = try makeEvent()
        let identifier = try Nostr.SubscriptionIdentifier("round")
        let subscription = try Nostr.RelaySubscription(
            identifier: identifier,
            filters: [try .init(kinds: [event.template.kind])]
        )

        try await session.subscribe(subscription)
        await connection.receive(
            textFrame(try relayEventFrame(identifier: identifier, event: event))
        )

        #expect(
            try await iterator.next()
                == .event(subscription: identifier, event: event)
        )
        try await session.closeSubscription(identifier)
        await session.stop()
        await session.stop()

        #expect(await connection.sentTexts.count == 2)
        #expect(await connection.closeCount == 1)
        #expect(await session.state == .terminal(.stopped))
    }

    @Test(
        "Reserve publication correlation before an awaited send",
        .timeLimit(.minutes(1))
    )
    func reservePublicationBeforeSend() async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        await connection.suspendNextSend()
        let session = try makeSession(connection: connection)
        let output = try await session.start()
        var iterator = output.makeAsyncIterator()
        await connection.waitUntilOpened()
        let event = try makeEvent()
        let identifier = hexadecimal(event.identifier.rawRepresentation)

        let publication = Task {
            try await session.publish(event)
        }
        await connection.waitUntilSendSuspends()
        await connection.receive(
            textFrame("[\"OK\",\"" + identifier + "\",true,\"saved\"]")
        )

        #expect(
            try await iterator.next()
                == .acknowledgement(
                    eventIdentifier: event.identifier,
                    accepted: true,
                    message: "saved"
                )
        )
        await connection.resumeSend()
        try await publication.value
        await session.stop()

        #expect(await connection.closeCount == 1)
    }

    @Test(
        "Terminalization unblocks every pending outbound operation",
        .timeLimit(.minutes(1)),
        arguments: OutboundOperation.allCases
    )
    func rejectPendingOutboundSuccess(_ operation: OutboundOperation) async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        let session = try makeSession(connection: connection)
        _ = try await session.start()
        let event = try makeEvent()
        let subscription = try Nostr.RelaySubscription(
            identifier: .init("pending"),
            filters: [try .init(kinds: [event.template.kind])]
        )
        if operation == .closeSubscription {
            try await session.subscribe(subscription)
        }
        await connection.suspendNextSend()

        let outbound = Task {
            switch operation {
            case .subscribe:
                try await session.subscribe(subscription)
            case .closeSubscription:
                try await session.closeSubscription(subscription.identifier)
            case .publish:
                try await session.publish(event)
            }
        }
        await connection.waitUntilSendSuspends()

        await session.stop()

        await #expect(throws: Session.Failure.notRunning) {
            try await outbound.value
        }
        #expect(await connection.closeCount == 1)
    }

    @Test("Reject unsolicited relay state as terminal", .timeLimit(.minutes(1)))
    func rejectUnsolicitedState() async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        let session = try makeSession(connection: connection)
        _ = try await session.start()
        await connection.waitUntilOpened()
        let identifier = try Nostr.SubscriptionIdentifier("unknown")

        await connection.receive(textFrame("[\"EOSE\",\"unknown\"]"))
        await session.waitForTermination()

        #expect(
            await session.state
                == .terminal(.failed(.unknownSubscription(identifier)))
        )
        #expect(await connection.closeCount == 1)
    }

    @Test("Reject binary input and do not fall back", .timeLimit(.minutes(1)))
    func rejectBinaryInput() async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        let session = try makeSession(connection: connection)
        _ = try await session.start()
        await connection.waitUntilOpened()

        await connection.receive(.binary(Data([0x01])))
        await session.waitForTermination()

        #expect(
            await session.state
                == .terminal(.failed(.binaryFrameReceived))
        )
        #expect(await connection.openCount == 1)
        #expect(await connection.closeCount == 1)
    }

    @Test("Enforce the byte limit at the injected connection boundary", .timeLimit(.minutes(1)))
    func enforceConnectionByteLimit() async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        let boundedLimits = try Nostr.RelayMessageCodingLimits(
            maximumFrameByteCount: 16,
            maximumFiltersPerRequest: 1,
            maximumValuesPerFilter: 1,
            maximumMessageStringByteCount: 16,
            event: eventLimits
        )
        let session = try Session(
            connection: connection,
            codingLimits: boundedLimits,
            maximumPendingOutputCount: 1
        )
        _ = try await session.start()

        await connection.receive(.text(Data(repeating: 0x61, count: 17)))
        await session.waitForTermination()

        #expect(
            await session.state
                == .terminal(.failed(.transportFailure))
        )
        #expect(await connection.openedMaximumIncomingMessageByteCount == 16)
        #expect(await connection.deliveredMessageCount == 0)
        #expect(await connection.rejectedIncomingMessageCount == 1)
    }

    @Test("Close on clean end and transport failure", .timeLimit(.minutes(1)), arguments: [false, true])
    func closeOnInputTermination(fails: Bool) async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        let session = try makeSession(connection: connection)
        _ = try await session.start()
        await connection.waitUntilOpened()

        if fails {
            await connection.failInput()
        } else {
            await connection.finishInput()
        }
        await session.waitForTermination()

        #expect(
            await session.state
                == (fails
                    ? .terminal(.failed(.transportFailure))
                    : .terminal(.inputEnded))
        )
        #expect(await connection.closeCount == 1)
    }

    @Test("Terminate when bounded output cannot be drained", .timeLimit(.minutes(1)))
    func terminateOnOutputOverflow() async throws {
        let connection = ScriptedMosaicTorWebSocketConnection()
        let session = try Session(
            connection: connection,
            codingLimits: limits,
            maximumPendingOutputCount: 1
        )
        _ = try await session.start()
        await connection.waitUntilOpened()

        await connection.receive(textFrame("[\"NOTICE\",\"one\"]"))
        await connection.receive(textFrame("[\"NOTICE\",\"two\"]"))
        await session.waitForTermination()

        #expect(
            await session.state
                == .terminal(.failed(.outputBufferOverflow))
        )
        #expect(await connection.closeCount == 1)
    }

    private var eventLimits: Nostr.EventCodingLimits {
        get throws {
            try .init(
                maximumEventJSONByteCount: 8_192,
                maximumTagCount: 16,
                maximumTagElementCount: 8,
                maximumStringByteCount: 4_096
            )
        }
    }

    private var limits: Nostr.RelayMessageCodingLimits {
        get throws {
            try .init(
                maximumFrameByteCount: 16_384,
                maximumFiltersPerRequest: 4,
                maximumValuesPerFilter: 16,
                maximumMessageStringByteCount: 4_096,
                event: eventLimits
            )
        }
    }

    private func makeSession(
        connection: ScriptedMosaicTorWebSocketConnection
    ) throws -> Session {
        try .init(
            connection: connection,
            codingLimits: limits,
            maximumPendingOutputCount: 8
        )
    }

    private func makeEvent() throws -> Nostr.Event {
        let signingKey = try OpalCrypto.Secp256k1.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31) + Data([2])
        )
        let template = try Nostr.EventTemplate(
            createdAt: 1_700_000_001,
            kind: 8,
            tags: [],
            content: "relay-session",
            limits: eventLimits
        )
        return try Nostr.EventSigner.sign(
            template,
            using: signingKey,
            auxiliaryRandomness: .init(
                rawRepresentation: Data(repeating: 0xB6, count: 32)
            ),
            limits: eventLimits
        )
    }

    private func relayEventFrame(
        identifier: Nostr.SubscriptionIdentifier,
        event: Nostr.Event
    ) throws -> String {
        let encoded = try Nostr.EventCodec.encode(event, limits: eventLimits)
        return "[\"EVENT\","
            + Nostr.EventCodec.encodeString(identifier.value)
            + "," + String(decoding: encoded, as: UTF8.self) + "]"
    }

    private func textFrame(_ value: String) -> OpalFusion.Mosaic.TorWebSocketMessage {
        .text(Data(value.utf8))
    }

    private func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
