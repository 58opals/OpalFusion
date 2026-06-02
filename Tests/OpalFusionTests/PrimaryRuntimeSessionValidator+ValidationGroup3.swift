// PrimaryRuntimeSessionValidator+ValidationGroup3.swift

@testable import OpalFusion
import Testing

extension PrimaryRuntimeSessionValidator {
    @Test("Primary runtime turns covert submission into a scripted covert request")
    func validateCovertSubmissionRequest() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)
        PrimaryRuntimeTestFixtures.markCovertPrepared(session: &session)

        let effects = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let firstEffect = try #require(effects.first)
        let request = try PrimaryRuntimeTestFixtures.extractCovertRequest(from: firstEffect)
        #expect(
            effects == [
                .performCovertRequest(
                    request: try PrimaryRuntimeTestFixtures.expectedRequest(
                        for: PrimaryRuntimeTestFixtures.covertComponentMessage,
                        startedAt: 1_035,
                        roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier
                    )
                ),
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .awaitingCommitments,
                        summary: "Submitting covert components"
                    )
                )
            ]
        )
        #expect(
            try PrimaryRuntimeTestFixtures.extractCovertMessage(from: request)
                == PrimaryRuntimeTestFixtures.covertComponentMessage
        )
        #expect(request.roundIdentifier == PrimaryRuntimeTestFixtures.roundIdentifier)
        #expect(session.covertSession.outstandingRequest == request)
    }

    @Test("Primary runtime advances after scripted covert acknowledgements")
    func validateCovertAcknowledgementAdvancement() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)
        PrimaryRuntimeTestFixtures.markCovertPrepared(session: &session)
        _ = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let effects = session.apply(
            input: .receivedCovertResponseBytes(
                try PrimaryRuntimeTestFixtures.encodeCovertResponsePayload(
                    PrimaryRuntimeTestFixtures.acknowledgement
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_036)
        )

        #expect(effects.isEmpty)
        #expect(session.engine.round?.substate == .awaitingSharedComponents)
        #expect(session.covertSession.outstandingRequest == nil)
    }

    @Test("Primary runtime clears covert state and surfaces close-start transport reset")
    func validateCloseStartResetClearsCovertSession() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession(
            baseline: PrimaryRuntimeTestFixtures.closeStartReachableBaseline
        )
        try PrimaryRuntimeTestFixtures.driveToAwaitingResult(session: &session)

        #expect(session.covertSession.endpointContext != nil)
        let effects = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_075)
        )

        #expect(effects == [.resetCovertTransport])
        #expect(session.engine.round?.substate == .awaitingResult)
        #expect(session.clientState.round?.phase == .assemblingTransaction)
        #expect(session.covertSession.substate == .idle)
        #expect(session.covertSession.endpointContext == nil)
        #expect(session.covertSession.queuedMessages.isEmpty)
        #expect(session.covertSession.outstandingRequest == nil)
        #expect(
            session.apply(
                input: .clockAdvanced,
                now: PrimaryRuntimeTestFixtures.instant(1_076)
            )
                .isEmpty
        )
    }

    @Test("Primary runtime clears covert state on restart while keeping the primary session alive")
    func validateRestartClearsCovertState() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingRestart(session: &session)

        let restartEffects = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .restartRound(.init())
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_060)
        )

        #expect(
            restartEffects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .status,
                        phase: .connecting,
                        summary: "Restarting round after blame handling"
                    )
                )
            ]
        )
        #expect(session.clientState.isConnected)
        #expect(session.clientState.round == nil)
        #expect(session.covertSession.substate == .idle)
        #expect(session.covertSession.endpointContext == nil)
        #expect(session.covertSession.queuedMessages.isEmpty)
        #expect(session.covertSession.outstandingRequest == nil)
    }

    @Test("Primary runtime ignores failure noise after terminal success")
    func validateTerminalSuccessIgnoresFailureNoise() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingResult(session: &session)
        _ = session.apply(
            input: .receivedPrimaryBytes(
                try PrimaryRuntimeTestFixtures.encodeServerFrame(
                    .fusionResult(PrimaryRuntimeTestFixtures.successResult)
                )
            ),
            now: PrimaryRuntimeTestFixtures.instant(1_055)
        )

        let effects = session.apply(
            input: .primaryTransportFailed(summary: "Primary read failed"),
            now: PrimaryRuntimeTestFixtures.instant(1_056)
        )

        #expect(effects.isEmpty)
        #expect(session.lastError == nil)
        #expect(
            session.clientState.round == .init(
                identifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                completionStatus: .success
            )
        )
    }

    @Test("Primary runtime maps host rejection to the existing coarse public failure surface")
    func validateHostRejectionProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveThroughStartRound(session: &session)

        let effects = session.apply(
            input: .participantReservationRejected,
            now: PrimaryRuntimeTestFixtures.instant(1_031)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Host rejected participant reservation",
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.clientState.round?.phase == .completed)
        #expect(session.clientState.round?.completionStatus == .hostRejected)
        #expect(session.lastError == .hostRejected)
    }
}
