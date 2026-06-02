// CovertRuntimeSessionValidator+ValidationGroup3.swift

@testable import OpalFusion
import Testing

extension CovertRuntimeSessionValidator {
    @Test("Covert runtime keeps queued request deadlines inside the original submit window")
    func validateQueuedRequestDeadlineUsesOriginalSubmitWindow() throws {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        let endpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
            entryPath: PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath,
            maxPayloadBytes: PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes,
            requestTimeoutMilliseconds: 10_000,
            connectTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.connectTimeout,
            connectWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.connectWindow,
            submitTimeout: .seconds(10),
            submitWindow: .seconds(5),
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )
        _ = session.apply(
            input: .prepare(endpointContext: endpoint),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.signatureMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        let firstEffects = session.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        guard case let .performCovertRequest(firstRequest)? = firstEffects.first else {
            Issue.record("Expected first covert request dispatch")
            return
        }
        #expect(firstRequest.deadline == PrimaryRuntimeTestFixtures.instant(1_005))

        let secondEffects = session.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_004)
        )
        guard case let .performCovertRequest(secondRequest)? = secondEffects.first else {
            Issue.record("Expected second covert request dispatch")
            return
        }
        #expect(secondRequest.startedAt == PrimaryRuntimeTestFixtures.instant(1_004))
        #expect(secondRequest.deadline == PrimaryRuntimeTestFixtures.instant(1_005))
    }

    @Test("Covert runtime starts the submit window when work is queued before preparation")
    func validateBufferedRequestUsesQueueTimeSubmitWindow() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        let endpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
            entryPath: PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath,
            maxPayloadBytes: PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes,
            requestTimeoutMilliseconds: 10_000,
            connectTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.connectTimeout,
            connectWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.connectWindow,
            submitTimeout: .seconds(10),
            submitWindow: .seconds(5),
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )
        _ = session.apply(
            input: .prepare(endpointContext: endpoint),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        let effects = session.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_006)
        )

        #expect(
            effects == [
                .emitTransportFailure(summary: "Covert request timed out")
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime times out queued work when the submit window elapses before preparation")
    func validateQueuedRequestTimesOutBeforePreparationCompletes() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        let endpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
            entryPath: PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath,
            maxPayloadBytes: PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes,
            requestTimeoutMilliseconds: 10_000,
            connectTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.connectTimeout,
            connectWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.connectWindow,
            submitTimeout: .seconds(10),
            submitWindow: .seconds(5),
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )
        _ = session.apply(
            input: .prepare(endpointContext: endpoint),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        let effects = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_006)
        )

        #expect(
            effects == [
                .emitTransportFailure(summary: "Covert request timed out")
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime surfaces malformed response bytes as protocol failure")
    func validateMalformedResponseFailure() throws {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))

        let effects = session.apply(
            input: .covertResponseBytesReceived([0x08]),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(effects.count == 1)
        let effect = try #require(effects.first)
        guard case let .emitProtocolFailure(summary) = effect else {
            Issue.record("Expected protocol failure after malformed covert response")
            return
        }
        #expect(summary == "Covert response decode failed")
        #expect(session.outstandingRequest == nil)
    }
}
