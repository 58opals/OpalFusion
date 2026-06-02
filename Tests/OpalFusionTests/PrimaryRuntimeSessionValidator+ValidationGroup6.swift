// PrimaryRuntimeSessionValidator+ValidationGroup6.swift

@testable import OpalFusion
import Testing

extension PrimaryRuntimeSessionValidator {
    @Test("Primary runtime maps covert request failures to transport failure")
    func validateCovertRequestFailureProjection() throws {
        var session = PrimaryRuntimeTestFixtures.makeSession()
        try PrimaryRuntimeTestFixtures.driveToAwaitingCovertSubmission(session: &session)
        PrimaryRuntimeTestFixtures.markCovertPrepared(session: &session)
        _ = session.apply(
            input: .clockAdvanced,
            now: PrimaryRuntimeTestFixtures.instant(1_035)
        )

        let effects = session.apply(
            input: .covertRequestFailed(summary: "Covert request failed"),
            now: PrimaryRuntimeTestFixtures.instant(1_036)
        )

        #expect(
            effects == [
                .emitHostEvent(
                    roundIdentifier: PrimaryRuntimeTestFixtures.roundIdentifier,
                    event: .init(
                        kind: .failure,
                        phase: .completed,
                        summary: "Covert request failed",
                        isTerminal: true
                    )
                )
            ]
        )
        #expect(session.lastError == .transportUnavailable)
        #expect(session.lastErrorSummary == "Covert request failed")
        #expect(session.clientState.round?.completionStatus == .transportFailed)
        #expect(session.covertSession.substate == .idle)
    }
}
