// OpalFusion+Execution+RoundEngine+HostEvent.swift

import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
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
