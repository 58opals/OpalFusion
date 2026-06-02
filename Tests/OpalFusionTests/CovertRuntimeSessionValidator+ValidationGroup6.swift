// CovertRuntimeSessionValidator+ValidationGroup6.swift

@testable import OpalFusion
import Testing

extension CovertRuntimeSessionValidator {
    @Test("Covert runtime clears prepared endpoint and queued work after request timeout")
    func validateRequestTimeoutClearsQueuedState() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.signatureMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        let timeoutEffects = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_005)
        )

        #expect(
            timeoutEffects == [
                .emitTransportFailure(summary: "Covert request timed out")
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime clears prepared endpoint after oversized payload failure")
    func validateOversizedPayloadFailureClearsPreparedState() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        let endpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
            entryPath: PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath,
            maxPayloadBytes: 1,
            requestTimeoutMilliseconds: PrimaryRuntimeTestFixtures.covertEndpointContext.requestTimeoutMilliseconds,
            connectTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.connectTimeout,
            connectWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.connectWindow,
            submitTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.submitTimeout,
            submitWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.submitWindow,
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )
        _ = session.apply(
            input: .prepare(endpointContext: endpoint),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))

        let effects = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.pingMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(
            effects == [
                .emitProtocolFailure(
                    summary: "Covert payload exceeded the configured size limit"
                )
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime clears prepared endpoint and queued work after late response timeout")
    func validateLateResponseTimeoutClearsQueuedState() throws {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.signatureMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        let timeoutEffects = session.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_005)
        )

        #expect(
            timeoutEffects == [
                .emitTransportFailure(summary: "Covert request timed out")
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime clears prepared endpoint and queued work after request failure")
    func validateRequestFailureClearsQueuedState() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.signatureMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        let failureEffects = session.apply(
            input: .covertRequestFailed(summary: "Covert request failed"),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(
            failureEffects == [
                .emitTransportFailure(summary: "Covert request failed")
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }
}
