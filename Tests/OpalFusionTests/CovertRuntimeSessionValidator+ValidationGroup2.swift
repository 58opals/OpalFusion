// CovertRuntimeSessionValidator+ValidationGroup2.swift

@testable import OpalFusion
import Testing

extension CovertRuntimeSessionValidator {
    @Test("Covert runtime delays acknowledgement delivery until queued submissions finish")
    func validateAcknowledgementDeliveryWaitsForQueuedSubmissions() throws {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        _ = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.signatureMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )

        let firstDispatchEffects = session.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_001)
        )
        #expect(
            firstDispatchEffects == [
                .performCovertRequest(
                    request: try PrimaryRuntimeTestFixtures.expectedRequest(
                        for: PrimaryRuntimeTestFixtures.covertComponentMessage,
                        startedAt: 1_001
                    )
                )
            ]
        )

        let firstResponseEffects = session.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )
        #expect(
            firstResponseEffects == [
                .performCovertRequest(
                    request: try PrimaryRuntimeTestFixtures.expectedRequest(
                        for: PrimaryRuntimeTestFixtures.signatureMessage,
                        startedAt: 1_002
                    )
                )
            ]
        )

        let finalResponseEffects = session.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_003)
        )
        #expect(
            finalResponseEffects == [
                .deliverCovertResponse(PrimaryRuntimeTestFixtures.acknowledgement)
            ]
        )
        #expect(session.outstandingRequest == nil)
        #expect(session.queuedMessages.isEmpty)
    }

    @Test("Covert runtime clears prepared endpoint after duplicate preparation callback")
    func validateDuplicatePreparationCallbackClearsPreparedState() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))

        let effects = session.apply(
            input: .covertPrepared,
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(
            effects == [
                .emitProtocolFailure(
                    summary: "Covert preparation completed before an endpoint was configured"
                )
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime caps request deadlines to the submit window")
    func validateRequestDeadlineDoesNotExceedSubmitWindow() throws {
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
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        guard case let .performCovertRequest(request)? = effects.first else {
            Issue.record("Expected covert request dispatch")
            return
        }
        #expect(request.deadline == PrimaryRuntimeTestFixtures.instant(1_005))
    }
}
