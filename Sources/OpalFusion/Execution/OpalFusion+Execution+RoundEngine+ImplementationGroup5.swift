// OpalFusion+Execution+RoundEngine+ImplementationGroup5.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    mutating func failForServerFailure(
        _ failure: OpalFusion.ProtocolModel.ServerFailure
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        let summary = serverFailureSummary(failure)
        let diagnosticFields = [
            OpalDiagnostics.Field.protocolErrorIdentifier(
                failure.sanitizedProtocolErrorIdentifier
            )
        ]

        if round?.identifier != nil {
            return failRound(
                completionStatus: .coordinatorRejected,
                clientError: .coordinatorRejected,
                summary: summary,
                diagnosticMessageKind: "ServerFailure",
                diagnosticFields: diagnosticFields
            )
        }

        return failBeforeRound(
            error: .coordinatorRejected,
            summary: summary,
            diagnosticMessageKind: "ServerFailure",
            diagnosticFields: diagnosticFields
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
                summary: workflowFailure.summary,
                diagnosticErrorCode: OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: workflowFailure),
                diagnosticFields: OpalDiagnostics.Field.workflowFailureFields(for: workflowFailure)
            )
        }

        return failRound(
            completionStatus: .hostRejected,
            clientError: .notImplemented,
            summary: "Execution materialization failed",
            diagnosticFields: [
                .validationBranch("execution_materialization"),
                .reasonCode("unknown")
            ]
        )
    }

    mutating func failBeforeRound(
        error: OpalFusion.Client.Error,
        summary: String,
        diagnosticMessageKind: String? = nil,
        diagnosticErrorCode: OpalDiagnostics.ErrorCode? = nil,
        diagnosticFields: [OpalDiagnostics.Field] = []
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        round = nil
        recordSessionFailure(error: error, summary: summary)
        var fields = [
            OpalDiagnostics.Field.operation("pre_round_failure"),
            OpalDiagnostics.Field.phase(.connecting)
        ]
        if let diagnosticMessageKind {
            fields.append(OpalDiagnostics.Field.messageKind(diagnosticMessageKind))
        }
        OpalDiagnostics.logger(category: .fusionRound).record(
            event: .roundFailed,
            level: .opalFusionDefault(for: .roundFailed),
            fields: fields + diagnosticFields
                + OpalDiagnostics.Field.sanitizedSummaryFields(
                    errorCode: diagnosticErrorCode ?? OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: error),
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
        summary: String,
        diagnosticMessageKind: String? = nil,
        diagnosticErrorCode: OpalDiagnostics.ErrorCode? = nil,
        diagnosticFields: [OpalDiagnostics.Field] = []
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard var round else {
            return failBeforeRound(
                error: clientError,
                summary: summary,
                diagnosticMessageKind: diagnosticMessageKind,
                diagnosticErrorCode: diagnosticErrorCode,
                diagnosticFields: diagnosticFields
            )
        }

        let previousMessageKind = lastRoundMessageKind(for: round)
        round.substate = .terminal
        round.completionStatus = completionStatus
        self.round = round
        recordSessionFailure(error: clientError, summary: summary)
        var fields = [
            OpalDiagnostics.Field.operation("round_failure"),
            OpalDiagnostics.Field.phase(.completed),
            OpalDiagnostics.Field.roundState(round.substate),
            OpalDiagnostics.Field.settlementState(completionStatus)
        ]
        if let messageKind = diagnosticMessageKind ?? previousMessageKind {
            fields.append(OpalDiagnostics.Field.messageKind(messageKind))
        }
        OpalDiagnostics.logger(category: .fusionRound).record(
            event: .roundFailed,
            level: .opalFusionDefault(for: .roundFailed),
            traceID: .opalFusionRound(round.identifier),
            fields: fields + diagnosticFields
                + OpalDiagnostics.Field.sanitizedSummaryFields(
                    errorCode: diagnosticErrorCode ?? OpalDiagnostics.ErrorCode.resolveOpalFusionCode(for: clientError),
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

    func lastRoundMessageKind(
        for round: OpalFusion.Execution.RoundContext
    ) -> String? {
        if round.theirProofsList != nil {
            return "TheirProofsList"
        }
        if round.fusionResult != nil {
            return "FusionResult"
        }
        if round.sharedComponents != nil {
            return "ShareCovertComponents"
        }
        if round.allCommitments != nil {
            return "AllCommitments"
        }
        if round.blindSignatureResponses != nil {
            return "BlindSignatureResponses"
        }
        if round.startRound != nil {
            return "StartRound"
        }

        return nil
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
