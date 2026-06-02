// CovertRuntimeSessionValidator+ValidationGroup5.swift

@testable import OpalFusion
import Testing

extension CovertRuntimeSessionValidator {
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

        var latePreparedSession = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = latePreparedSession.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = latePreparedSession.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        let latePreparedEffects = latePreparedSession.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_016)
        )
        #expect(
            latePreparedEffects == [
                .emitTransportFailure(summary: "Covert endpoint preparation timed out")
            ]
        )
        #expect(latePreparedSession.outstandingRequest == nil)

        var lateResponseSession = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = lateResponseSession.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = lateResponseSession.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        _ = lateResponseSession.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        let lateResponseEffects = lateResponseSession.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_005)
        )
        #expect(
            lateResponseEffects == [
                .emitTransportFailure(summary: "Covert request timed out")
            ]
        )
        #expect(lateResponseSession.outstandingRequest == nil)

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

    @Test("Covert runtime clears prepared endpoint and queued work after preparation timeout")
    func validatePreparationTimeoutClearsQueuedState() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )

        let timeoutEffects = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_016)
        )

        #expect(
            timeoutEffects == [
                .emitTransportFailure(summary: "Covert endpoint preparation timed out")
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime clears prepared endpoint and queued work after preparation failure")
    func validatePreparationFailureClearsQueuedState() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )

        let failureEffects = session.apply(
            input: .covertPreparationFailed(summary: "Covert preparation failed"),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(
            failureEffects == [
                .emitTransportFailure(summary: "Covert preparation failed")
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }
}
