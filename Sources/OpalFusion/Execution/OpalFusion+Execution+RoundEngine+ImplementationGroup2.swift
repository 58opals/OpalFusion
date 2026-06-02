// OpalFusion+Execution+RoundEngine+ImplementationGroup2.swift

import Foundation

extension OpalFusion.Execution.RoundEngine {
    mutating func handlePrimaryMessage(
        _ message: OpalFusion.ProtocolModel.ServerMessage,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if round?.substate == .terminal {
            return []
        }

        if case let .serverFailure(failure) = message {
            return failForServerFailure(failure)
        }

        if round == nil {
            return handlePreRoundPrimaryMessage(message, now: now)
        }

        return handleRoundPrimaryMessage(message, now: now)
    }

    mutating func handleRoundPrimaryMessage(
        _ message: OpalFusion.ProtocolModel.ServerMessage,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard var round else {
            return []
        }

        switch message {
        case let .startRound(startRound):
            return handleStartRound(startRound, round: &round, now: now)
        case let .blindSignatureResponses(responses):
            return handleBlindSignatureResponses(responses, round: &round)
        case let .allCommitments(allCommitments):
            return handleAllCommitments(allCommitments, round: &round, now: now)
        case let .shareCovertComponents(sharedComponents):
            return handleShareCovertComponents(sharedComponents, round: &round)
        case let .fusionResult(result):
            return handleFusionResult(result, round: &round)
        case let .theirProofsList(theirProofsList):
            return handleTheirProofsList(theirProofsList, round: &round)
        case .restartRound:
            return handleRestartRound(round: round)
        case .serverHello, .tierStatusUpdate, .fusionBegin:
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "Received an unexpected coordinator message mid-round"
            )
        case .serverFailure:
            return []
        }
    }
}
