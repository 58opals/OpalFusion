// OpalFusion+Execution+RoundEngine+ImplementationGroup5.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    mutating func failForServerFailure(
        _ failure: OpalFusion.ProtocolModel.ServerFailure
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        let summary = serverFailureSummary(failure)

        if round?.identifier != nil {
            return failRound(
                completionStatus: .coordinatorRejected,
                clientError: .coordinatorRejected,
                summary: summary
            )
        }

        return failBeforeRound(
            error: .coordinatorRejected,
            summary: summary
        )
    }

    func serverFailureSummary(
        _ failure: OpalFusion.ProtocolModel.ServerFailure
    ) -> String {
        guard let message = failure.message,
              message.contains(where: { $0.isWhitespace == false }) else {
            return "Coordinator rejected the current flow"
        }

        return message
    }

    mutating func failForWorkflowFailure(
        _ error: Swift.Error
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if let workflowFailure = error as? OpalFusion.Execution.WorkflowFailure {
            return failRound(
                completionStatus: workflowFailure.completionStatus,
                clientError: workflowFailure.clientError,
                summary: workflowFailure.summary
            )
        }

        return failRound(
            completionStatus: .hostRejected,
            clientError: .notImplemented,
            summary: "Execution materialization failed"
        )
    }

    mutating func failBeforeRound(
        error: OpalFusion.Client.Error,
        summary: String
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        round = nil
        recordSessionFailure(error: error, summary: summary)
        OpalDiagnostics.logger(category: .fusionRound).record(
            event: .roundFailed,
            level: .opalFusionDefault(for: .roundFailed),
            fields: [
                .operation("pre_round_failure"),
                .phase(.connecting)
            ] + OpalDiagnostics.Field.sanitizedSummaryFields(
                errorCode: OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: error),
                summary: summary
            )
        )
        return [
            hostEventWithoutDiagnostics(
                roundIdentifier: nil,
                kind: .failure,
                phase: .connecting,
                summary: summary
            )
        ]
    }

    mutating func failActiveFlow(
        completionStatus: OpalFusion.Round.CompletionStatus,
        clientError: OpalFusion.Client.Error,
        summary: String
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if round?.substate == .terminal {
            return []
        }

        guard round?.identifier != nil else {
            return failBeforeRound(
                error: clientError,
                summary: summary
            )
        }

        return failRound(
            completionStatus: completionStatus,
            clientError: clientError,
            summary: summary
        )
    }

    mutating func failRound(
        completionStatus: OpalFusion.Round.CompletionStatus,
        clientError: OpalFusion.Client.Error,
        summary: String
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard var round else {
            return failBeforeRound(
                error: clientError,
                summary: summary
            )
        }

        round.substate = .terminal
        round.completionStatus = completionStatus
        self.round = round
        recordSessionFailure(error: clientError, summary: summary)
        OpalDiagnostics.logger(category: .fusionRound).record(
            event: .roundFailed,
            level: .opalFusionDefault(for: .roundFailed),
            traceID: .opalFusionRound(round.identifier),
            fields: [
                .operation("round_failure"),
                .phase(.completed),
                .roundState(round.substate),
                .settlementState(completionStatus)
            ] + OpalDiagnostics.Field.sanitizedSummaryFields(
                errorCode: OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: clientError),
                summary: summary
            )
        )

        return [
            hostEventWithoutDiagnostics(
                roundIdentifier: round.identifier,
                kind: .failure,
                phase: .completed,
                summary: summary,
                isTerminal: true
            )
        ]
    }

    mutating func recordSessionFailure(
        error: OpalFusion.Client.Error,
        summary: String
    ) {
        session.isConnected = false
        session.lastError = error
        session.lastErrorSummary = summary
        session.connectionSubstate = .failed
    }

    func hostEvent(
        roundIdentifier: OpalFusion.Round.Identifier?,
        kind: OpalFusion.Host.Event.Kind,
        phase: OpalFusion.Round.Phase,
        summary: String,
        isTerminal: Bool = false,
        errorCode: OpalDiagnostics.ErrorCode? = nil
    ) -> OpalFusion.Execution.RoundEngine.Effect {
        recordHostEventDiagnostics(
            roundIdentifier: roundIdentifier,
            kind: kind,
            phase: phase,
            summary: summary,
            isTerminal: isTerminal,
            errorCode: errorCode
        )
        return hostEventWithoutDiagnostics(
            roundIdentifier: roundIdentifier,
            kind: kind,
            phase: phase,
            summary: summary,
            isTerminal: isTerminal
        )
    }
}
