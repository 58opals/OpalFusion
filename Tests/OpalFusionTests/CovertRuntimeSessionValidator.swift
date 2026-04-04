// CovertRuntimeSessionValidator.swift

@testable import OpalFusion
import Testing

struct CovertRuntimeSessionValidator {
    @Test("Covert runtime emits a preparation effect from FusionBegin-derived endpoint context")
    func validatePreparationEffect() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()

        let effects = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        #expect(
            effects == [
                .prepareCovertEndpoint(
                    plan: PrimaryRuntimeTestFixtures.expectedPreparationPlan(startedAt: 1_000)
                )
            ]
        )
        #expect(session.substate == .preparing)
        #expect(session.endpointContext == PrimaryRuntimeTestFixtures.covertEndpointContext)
        #expect(session.queuedMessages.isEmpty)
    }

    @Test("Covert runtime buffers queued work before preparation completes")
    func validateQueuedMessageBuffering() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        let effects = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        #expect(effects.isEmpty)
        #expect(session.queuedMessages == [PrimaryRuntimeTestFixtures.covertComponentMessage])
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime decodes successful scripted acknowledgements")
    func validateAcknowledgementDecode() throws {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let dispatchEffects = session.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        #expect(
            dispatchEffects == [
                .performCovertRequest(
                    request: try PrimaryRuntimeTestFixtures.expectedRequest(
                        for: PrimaryRuntimeTestFixtures.covertComponentMessage,
                        startedAt: 1_001
                    )
                )
            ]
        )

        let responseEffects = session.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(
            responseEffects == [
                .deliverCovertResponse(PrimaryRuntimeTestFixtures.acknowledgement)
            ]
        )
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime surfaces malformed response bytes as protocol failure")
    func validateMalformedResponseFailure() {
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
        guard case let .emitProtocolFailure(summary) = effects[0] else {
            Issue.record("Expected protocol failure after malformed covert response")
            return
        }
        #expect(summary.hasPrefix("Covert response decode failed:"))
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime maps preparation timeout and request failure to transport failure")
    func validateTransportFailurePaths() throws {
        var timedOutSession = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = timedOutSession.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        let timeoutEffects = timedOutSession.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_016)
        )
        #expect(
            timeoutEffects == [
                .emitTransportFailure(summary: "Covert endpoint preparation timed out")
            ]
        )

        var failedRequestSession = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = failedRequestSession.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = failedRequestSession.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )
        _ = failedRequestSession.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        let failureEffects = failedRequestSession.apply(
            input: .covertRequestFailed(summary: "Covert request failed"),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )
        #expect(
            failureEffects == [
                .emitTransportFailure(summary: "Covert request failed")
            ]
        )
    }

    @Test("Covert runtime reset clears queued work and outstanding request state")
    func validateReset() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )
        _ = session.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )

        let effects = session.apply(
            input: .reset,
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(effects.isEmpty)
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }
}
