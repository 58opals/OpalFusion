// CovertRuntimeSessionValidator+ValidationGroup1.swift

@testable import OpalFusion
import Testing

extension CovertRuntimeSessionValidator {
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

    @Test("Covert runtime clamps huge connect-window deadlines without trapping")
    func validateHugeConnectWindowDeadline() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        let endpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
            entryPath: PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath,
            maxPayloadBytes: PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes,
            requestTimeoutMilliseconds: PrimaryRuntimeTestFixtures.covertEndpointContext.requestTimeoutMilliseconds,
            connectTimeout: .seconds(Int64.max),
            connectWindow: .seconds(Int64.max),
            submitTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.submitTimeout,
            submitWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.submitWindow,
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )

        let effects = session.apply(
            input: .prepare(endpointContext: endpoint),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        #expect(
            effects == [
                .prepareCovertEndpoint(
                    plan: .init(
                        endpoint: endpoint,
                        startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
                        deadline: .init(millisecondsSinceUnixEpoch: Int64.max)
                    )
                )
            ]
        )
    }

    @Test("Covert runtime caps preparation deadlines to the connect timeout")
    func validatePreparationDeadlineUsesConnectTimeout() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        let endpoint = OpalFusion.Runtime.CovertEndpointContext(
            roundIdentifier: PrimaryRuntimeTestFixtures.covertEndpointContext.roundIdentifier,
            host: PrimaryRuntimeTestFixtures.covertEndpointContext.host,
            port: PrimaryRuntimeTestFixtures.covertEndpointContext.port,
            requiresTLS: PrimaryRuntimeTestFixtures.covertEndpointContext.requiresTLS,
            entryPath: PrimaryRuntimeTestFixtures.covertEndpointContext.entryPath,
            maxPayloadBytes: PrimaryRuntimeTestFixtures.covertEndpointContext.maxPayloadBytes,
            requestTimeoutMilliseconds: PrimaryRuntimeTestFixtures.covertEndpointContext.requestTimeoutMilliseconds,
            connectTimeout: .seconds(3),
            connectWindow: .seconds(15),
            submitTimeout: PrimaryRuntimeTestFixtures.covertEndpointContext.submitTimeout,
            submitWindow: PrimaryRuntimeTestFixtures.covertEndpointContext.submitWindow,
            spareConnectionCount: PrimaryRuntimeTestFixtures.covertEndpointContext.spareConnectionCount
        )

        let effects = session.apply(
            input: .prepare(endpointContext: endpoint),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        #expect(
            effects == [
                .prepareCovertEndpoint(
                    plan: .init(
                        endpoint: endpoint,
                        startedAt: PrimaryRuntimeTestFixtures.instant(1_000),
                        deadline: PrimaryRuntimeTestFixtures.instant(1_003)
                    )
                )
            ]
        )
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

    @Test("Covert runtime rejects queued work before endpoint preparation")
    func validateQueuedMessageBeforePreparationFails() {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()

        let effects = session.apply(
            input: .enqueue(message: PrimaryRuntimeTestFixtures.covertComponentMessage),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )

        #expect(
            effects == [
                .emitProtocolFailure(
                    summary: "Covert request was queued before an endpoint was configured"
                )
            ]
        )
        #expect(session.queuedMessages.isEmpty)
        #expect(session.substate == .idle)
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
}
