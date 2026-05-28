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

    @Test("Covert runtime clears prepared endpoint and queued work after malformed response")
    func validateMalformedResponseClearsQueuedState() throws {
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
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime stops queued dispatch after coordinator server failure response")
    func validateServerFailureResponseClearsQueuedState() throws {
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

        let effects = session.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.covertFailureResponse
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(
            effects == [
                .deliverCovertResponse(PrimaryRuntimeTestFixtures.covertFailureResponse)
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
        #expect(session.outstandingRequest == nil)
    }

    @Test("Covert runtime clears prepared endpoint after unsolicited response")
    func validateUnsolicitedResponseClearsPreparedState() throws {
        var session = PrimaryRuntimeTestFixtures.makeCovertSession()
        _ = session.apply(
            input: .prepare(endpointContext: PrimaryRuntimeTestFixtures.covertEndpointContext),
            now: PrimaryRuntimeTestFixtures.instant(1_000)
        )
        _ = session.apply(input: .covertPrepared, now: PrimaryRuntimeTestFixtures.instant(1_001))

        let effects = session.apply(
            input: .covertResponseBytesReceived(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_002)
        )

        #expect(
            effects == [
                .emitProtocolFailure(
                    summary: "Received a covert response without an outstanding request"
                )
            ]
        )
        #expect(session.substate == .idle)
        #expect(session.endpointContext == nil)
        #expect(session.preparationPlan == nil)
        #expect(session.queuedMessages.isEmpty)
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
