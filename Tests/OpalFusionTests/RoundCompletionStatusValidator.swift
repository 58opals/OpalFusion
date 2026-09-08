// RoundCompletionStatusValidator.swift

import OpalFusion
import Testing

struct RoundCompletionStatusValidator {
    @Test("Round state preserves nonterminal construction without a completion status")
    func validateNonterminalRoundStateConstruction() {
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-001"),
            phase: .connecting
        )

        #expect(round.phase == .connecting)
        #expect(round.participantCount == nil)
        #expect(round.completionStatus == nil)
        #expect(round.isTerminal == false)
    }

    @Test(
        "Round state supports completed terminal snapshots with explicit completion status",
        arguments: [
            OpalFusion.Round.CompletionStatus.success,
            .coordinatorRejected,
            .hostRejected,
            .protocolIncompatible,
            .transportFailed,
            .blameRequired
        ]
    )
    func validateTerminalRoundSnapshots(status: OpalFusion.Round.CompletionStatus) {
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-terminal"),
            participantCount: 8,
            completionStatus: status
        )

        #expect(round.phase == .completed)
        #expect(round.participantCount == 8)
        #expect(round.completionStatus == status)
        #expect(round.isTerminal == true)
    }

    @Test("Blame phase remains nonterminal when no completion status is present")
    func validateBlamePhaseConstruction() {
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-blame"),
            phase: .blame
        )

        #expect(round.phase == .blame)
        #expect(round.completionStatus == nil)
        #expect(round.isTerminal == false)
    }
}
