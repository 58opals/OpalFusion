// OpalFusion+Execution+RoundEngine+ResultAndBlameMessages.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    mutating func handleFusionResult(
        _ result: OpalFusion.ProtocolModel.FusionResult,
        round: inout OpalFusion.Execution.RoundContext
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard round.substate == .submittingSignatures ||
                round.substate == .awaitingResult else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "FusionResult arrived out of order"
            )
        }

        round.fusionResult = result
        if result.isSuccess {
            return completeSuccessfulRound(round: &round)
        }

        let myProofsList: OpalFusion.ProtocolModel.MyProofsList
        do {
            myProofsList = try workflow.buildMyProofsList(&round)
        } catch {
            return failForWorkflowFailure(error)
        }
        round.myProofsList = myProofsList
        round.substate = .awaitingTheirProofs
        self.round = round

        return [
            .sendPrimary(.myProofsList(myProofsList)),
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .warning,
                phase: .blame,
                summary: "Round result requires blame handling"
            )
        ]
    }

    mutating func completeSuccessfulRound(
        round: inout OpalFusion.Execution.RoundContext
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if round.sharedComponents?.skipSignatures == true {
            self.round = round
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "FusionResult reported success after signatures were skipped"
            )
        }

        round.substate = .terminal
        round.completionStatus = .success
        self.round = round
        OpalDiagnostics.logger(category: .fusionRound).record(
            event: .roundCompleted,
            level: .opalFusionDefault(for: .roundCompleted),
            traceID: .opalFusionRound(round.identifier),
            fields: [
                .operation("round_complete"),
                .phase(.completed),
                .roundState(round.substate),
                .settlementState(.success)
            ]
        )
        return [
            hostEventWithoutDiagnostics(
                roundIdentifier: round.identifier,
                kind: .completed,
                phase: .completed,
                summary: "Round completed successfully",
                isTerminal: true
            )
        ]
    }

    mutating func handleTheirProofsList(
        _ theirProofsList: OpalFusion.ProtocolModel.TheirProofsList,
        round: inout OpalFusion.Execution.RoundContext
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard round.substate == .awaitingTheirProofs else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "TheirProofsList arrived out of order"
            )
        }

        round.theirProofsList = theirProofsList
        let blames: OpalFusion.ProtocolModel.Blames
        do {
            blames = try workflow.buildBlames(&round)
        } catch {
            recordBlameBuildFailure(error, round: round)
            return failForWorkflowFailure(error)
        }
        round.blames = blames
        round.substate = .submittingBlames
        self.round = round

        round.substate = .awaitingRestart
        self.round = round
        OpalDiagnostics.logger(category: .fusionBlame).record(
            event: .blameSubmissionStarted,
            level: .opalFusionDefault(for: .blameSubmissionStarted),
            traceID: .opalFusionRound(round.identifier),
            fields: [
                .operation("blame_submit"),
                .phase(.blame),
                .roundState(round.substate),
                .messageKind("Blames")
            ]
        )

        return [
            .sendPrimary(.blames(blames)),
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .warning,
                phase: .blame,
                summary: "Submitting blame proofs and awaiting restart"
            )
        ]
    }

    func recordBlameBuildFailure(
        _ error: Error,
        round: OpalFusion.Execution.RoundContext
    ) {
        OpalDiagnostics.logger(category: .fusionBlame).record(
            event: .blameProofValidationFailed,
            level: .opalFusionDefault(for: .blameProofValidationFailed),
            traceID: .opalFusionRound(round.identifier),
            fields: [
                .operation("blame_build"),
                .phase(.blame),
                .roundState(round.substate)
            ] + OpalDiagnostics.Field.errorFields(for: error)
        )
    }

    mutating func handleRestartRound(
        round: OpalFusion.Execution.RoundContext
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard round.substate == .awaitingRestart else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "RestartRound arrived out of order"
            )
        }

        let priorIdentifier = round.identifier
        self.round = nil
        session.restartCount += 1
        session.connectionSubstate = .awaitingFusionBegin
        OpalDiagnostics.logger(category: .fusionRound).record(
            event: .roundRestarted,
            level: .opalFusionDefault(for: .roundRestarted),
            traceID: .opalFusionRound(priorIdentifier),
            fields: [
                .operation("round_restart"),
                .phase(.connecting)
            ]
        )

        return [
            hostEvent(
                roundIdentifier: priorIdentifier,
                kind: .status,
                phase: .connecting,
                summary: "Restarting round after blame handling"
            )
        ]
    }
}
