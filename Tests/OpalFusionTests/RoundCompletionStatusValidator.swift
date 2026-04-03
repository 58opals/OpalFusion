// RoundCompletionStatusValidator.swift

import OpalFusion
import Testing

struct RoundCompletionStatusValidator {
    @Test("Round completion status exposes the documented terminal outcomes")
    func validateCompletionStatusCases() {
        let statuses: [OpalFusion.Round.CompletionStatus] = [
            .success,
            .coordinatorRejected,
            .hostRejected,
            .protocolIncompatible,
            .transportFailed,
            .blameRequired
        ]

        #expect(statuses.count == 6)
        #expect(Self.requireSendable(statuses[0]) == .success)
        #expect(statuses[1] == .coordinatorRejected)
        #expect(statuses[2] == .hostRejected)
        #expect(statuses[3] == .protocolIncompatible)
        #expect(statuses[4] == .transportFailed)
        #expect(statuses[5] == .blameRequired)
    }

    @Test("Round state preserves backward-compatible construction without a completion status")
    func validateLegacyRoundStateConstruction() {
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-001"),
            phase: .connecting
        )

        #expect(round.phase == .connecting)
        #expect(round.participantCount == nil)
        #expect(round.completionStatus == nil)
        #expect(round.isTerminal == false)
    }

    @Test("Round state supports completed terminal snapshots with explicit completion status")
    func validateTerminalRoundSnapshots() {
        let statuses: [OpalFusion.Round.CompletionStatus] = [
            .success,
            .coordinatorRejected,
            .hostRejected,
            .protocolIncompatible,
            .transportFailed,
            .blameRequired
        ]

        for status in statuses {
            let round = OpalFusion.Round.State(
                identifier: .init(rawValue: "round-terminal"),
                phase: .completed,
                participantCount: 8,
                completionStatus: status,
                isTerminal: true
            )

            #expect(round.phase == .completed)
            #expect(round.participantCount == 8)
            #expect(round.completionStatus == status)
            #expect(round.isTerminal == true)
        }
    }

    @Test("Blame phase remains nonterminal when no completion status is present")
    func validateBlamePhaseConstruction() {
        let round = OpalFusion.Round.State(
            identifier: .init(rawValue: "round-blame"),
            phase: .blame,
            completionStatus: nil,
            isTerminal: false
        )

        #expect(round.phase == .blame)
        #expect(round.completionStatus == nil)
        #expect(round.isTerminal == false)
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
