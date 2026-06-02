// CovertRuntimeSessionValidator+ValidationGroup4.swift

@testable import OpalFusion
import Testing

extension CovertRuntimeSessionValidator {
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
}
