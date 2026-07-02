// OpalFusion+Execution+RoundEngine+CommitmentMessages.swift

import Foundation

extension OpalFusion.Execution.RoundEngine {
    mutating func handleBlindSignatureResponses(
        _ responses: OpalFusion.ProtocolModel.BlindSignatureResponses,
        round: inout OpalFusion.Execution.RoundContext
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard round.substate == .awaitingBlindSignatures else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "Blind signature responses arrived out of order"
            )
        }
        guard let playerCommit = round.playerCommit,
              responses.responses.count == playerCommit.blindSignatureRequests.count else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "Blind signature response count did not match PlayerCommit request count"
            )
        }

        round.blindSignatureResponses = responses
        round.substate = .awaitingAllCommitments
        self.round = round

        return [
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .awaitingCommitments,
                summary: "Blind signature responses received"
            )
        ]
    }

    mutating func handleAllCommitments(
        _ allCommitments: OpalFusion.ProtocolModel.AllCommitments,
        round: inout OpalFusion.Execution.RoundContext,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard round.substate == .awaitingAllCommitments else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "AllCommitments arrived out of order"
            )
        }
        let receivedCommitments = Set(allCommitments.initialCommitments)
        guard let playerCommit = round.playerCommit,
              playerCommit.initialCommitments.allSatisfy(receivedCommitments.contains) else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "AllCommitments omitted a local commitment"
            )
        }
        guard receivedCommitments.count == allCommitments.initialCommitments.count else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "AllCommitments contained duplicate commitments"
            )
        }

        round.allCommitments = allCommitments
        round.substate = .awaitingCovertComponentWindow
        self.round = round

        var effects = [
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .awaitingCommitments,
                summary: "All commitments received; waiting for covert submit window"
            )
        ]
        effects.append(contentsOf: maybeOpenCovertSubmission(now: now))
        return effects
    }
}
