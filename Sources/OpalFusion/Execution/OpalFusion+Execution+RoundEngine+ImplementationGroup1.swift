// OpalFusion+Execution+RoundEngine+ImplementationGroup1.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    mutating func apply(
        input: OpalFusion.Execution.RoundEngine.Input,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        switch input {
        case let .configurationRejected(summary):
            session.isConnected = false
            return failBeforeRound(
                error: .invalidConfiguration,
                summary: summary
            )
        case .primaryConnected:
            return handlePrimaryConnected()
        case .primaryDisconnected:
            return handlePrimaryDisconnected()
        case .stopped:
            return handleStopped()
        case let .primaryTransportFailed(summary):
            if session.connectionSubstate == .failed {
                session.isConnected = false
                return []
            }
            session.isConnected = false
            if round?.substate == .terminal {
                session.connectionSubstate = .disconnected
                return []
            }
            return failActiveFlow(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: summary
            )
        case let .covertTransportFailed(summary):
            return failActiveFlow(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: summary
            )
        case let .protocolRejected(summary):
            return failActiveFlow(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: summary
            )
        case let .primaryMessage(message):
            return handlePrimaryMessage(message, now: now)
        case let .covertResponse(response):
            return handleCovertResponse(response)
        case let .participantReservationLoaded(reservation):
            return handleParticipantReservationLoaded(reservation, now: now)
        case .participantReservationRejected:
            if round?.substate == .terminal {
                return []
            }
            return failRound(
                completionStatus: .hostRejected,
                clientError: .hostRejected,
                summary: "Host rejected participant reservation"
            )
        case let .finalizedTransactionLoaded(transaction):
            return handleFinalizedTransactionLoaded(transaction, now: now)
        case let .transactionFinalizationRejected(failure):
            if round?.substate == .terminal {
                return []
            }
            OpalDiagnostics.logger(category: .fusionTransaction).record(
                event: .transactionFinalizationFailed,
                level: .opalFusionDefault(for: .transactionFinalizationFailed),
                traceID: .opalFusionRound(round?.identifier),
                fields: [
                    .operation("transaction_finalization")
                ] + OpalDiagnostics.Field.errorFields(for: failure)
            )
            return failRound(
                completionStatus: failure.completionStatus,
                clientError: failure.clientError,
                summary: failure.summary
            )
        case .clockAdvanced:
            return handleClockAdvanced(now: now)
        }
    }

    mutating func handlePrimaryConnected() -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard session.connectionSubstate == .disconnected else {
            return []
        }

        session.isConnected = true
        session.connectionSubstate = .awaitingServerHello
        session.lastError = nil
        session.lastErrorSummary = nil

        let hello = OpalFusion.ProtocolModel.ClientHello(
            versionBytes: session.baseline.protocolIdentity.versionBytes,
            genesisHash: session.genesisHash
        )

        return [
            .sendPrimary(.clientHello(hello)),
            hostEvent(
                roundIdentifier: nil,
                kind: .status,
                phase: .connecting,
                summary: "Primary channel connected; sending ClientHello"
            )
        ]
    }

    mutating func handlePrimaryDisconnected() -> [OpalFusion.Execution.RoundEngine.Effect] {
        session.isConnected = false

        if session.connectionSubstate == .failed {
            return []
        }

        if round?.substate == .terminal {
            session.connectionSubstate = .disconnected
            return []
        }

        if round?.identifier != nil {
            return failRound(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: "Primary channel disconnected"
            )
        }

        round = nil
        session.connectionSubstate = .disconnected
        session.lastError = .transportUnavailable
        session.lastErrorSummary = "Primary channel disconnected"
        return [
            hostEvent(
                roundIdentifier: nil,
                kind: .failure,
                phase: .connecting,
                summary: "Primary channel disconnected",
                errorCode: .transportUnavailable
            )
        ]
    }

    mutating func handleStopped() -> [OpalFusion.Execution.RoundEngine.Effect] {
        session.isConnected = false
        session.connectionSubstate = .disconnected
        session.lastError = nil
        session.lastErrorSummary = nil

        if round?.substate != .terminal {
            round = nil
        }

        return []
    }
}
