// RoundCompletionStatusValidator.swift

import OpalFusion
import Testing

struct RoundCompletionStatusValidator {
    @Test("Round completion status exposes the documented terminal outcomes")
    func validateCompletionStatusCases() throws {
        let statuses: [OpalFusion.Round.CompletionStatus] = [
            .success,
            .coordinatorRejected,
            .hostRejected,
            .protocolIncompatible,
            .transportFailed,
            .blameRequired
        ]

        #expect(statuses.count == 6)
        #expect(Self.requireSendable(try #require(statuses.first)) == .success)
        #expect(try #require(statuses.dropFirst().first) == .coordinatorRejected)
        #expect(try #require(statuses.dropFirst(2).first) == .hostRejected)
        #expect(try #require(statuses.dropFirst(3).first) == .protocolIncompatible)
        #expect(try #require(statuses.dropFirst(4).first) == .transportFailed)
        #expect(try #require(statuses.dropFirst(5).first) == .blameRequired)
    }

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
                participantCount: 8,
                completionStatus: status
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
            phase: .blame
        )

        #expect(round.phase == .blame)
        #expect(round.completionStatus == nil)
        #expect(round.isTerminal == false)
    }

    static func requireSendable<Value: Sendable>(_ value: Value) -> Value {
        value
    }
}
