// OpalFusion+Execution+RoundEngine+StartRoundMessage.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    mutating func handleStartRound(
        _ startRound: OpalFusion.ProtocolModel.StartRound,
        round: inout OpalFusion.Execution.RoundContext,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard round.substate == .warmup else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "StartRound arrived out of order"
            )
        }
        guard isServerTimeAcceptable(startRound.serverTimeUnixSeconds, now: now) else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "StartRound server time exceeded the allowed clock skew"
            )
        }
        guard startRound.blindNoncePoints.count == Int(round.serverHello.numberOfComponents) else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "StartRound blind nonce count did not match ServerHello component count"
            )
        }
        guard startRound.roundPublicKey.isEmpty == false else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "StartRound round public key was missing"
            )
        }
        guard startRound.blindNoncePoints.allSatisfy({ $0.isEmpty == false }) else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "StartRound blind nonce point was missing"
            )
        }

        let roundIdentifier = makeRoundIdentifier(from: startRound.roundPublicKey)
        let reservationContext = makeParticipantReservationContext(
            roundIdentifier: roundIdentifier,
            fusionBegin: round.fusionBegin,
            serverHello: round.serverHello
        )

        round.startRound = startRound
        round.identifier = roundIdentifier
        round.deadlines = round.deadlines.withStartRound(
            startRound,
            timing: session.baseline.roundTiming
        )
        round.substate = .collectingInputs
        self.round = round
        OpalDiagnostics.logger(category: .fusionRound).record(
            event: .roundEntered,
            level: .opalFusionDefault(for: .roundEntered),
            traceID: .opalFusionRound(roundIdentifier),
            fields: [
                .operation("round_enter"),
                .phase(.registeringInputs),
                .roundState(round.substate),
                .messageKind("StartRound")
            ]
        )

        return [
            .requestParticipantReservation(context: reservationContext),
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .registeringInputs,
                summary: "StartRound received; collecting reserved inputs and outputs"
            )
        ]
    }
}
