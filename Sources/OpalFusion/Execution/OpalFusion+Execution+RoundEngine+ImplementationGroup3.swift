// OpalFusion+Execution+RoundEngine+ImplementationGroup3.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    mutating func handleCovertResponse(
        _ response: OpalFusion.ProtocolModel.CovertResponse
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if round?.substate == .terminal {
            return []
        }

        switch response {
        case .acknowledgement:
            guard var round else {
                return failBeforeRound(
                    error: .protocolIncompatible,
                    summary: "Covert acknowledgement arrived out of order"
                )
            }

            switch round.substate {
            case .submittingCovertComponents:
                round.substate = .awaitingSharedComponents
                self.round = round
            case .submittingSignatures:
                round.substate = .awaitingResult
                self.round = round
            default:
                return failRound(
                    completionStatus: .protocolIncompatible,
                    clientError: .protocolIncompatible,
                    summary: "Covert acknowledgement arrived out of order"
                )
            }

            return []
        case let .serverFailure(failure):
            return failForServerFailure(failure)
        }
    }

    mutating func handleParticipantReservationLoaded(
        _ reservation: OpalFusion.Host.ParticipantReservation,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if round?.substate == .terminal {
            return []
        }

        guard var round, round.substate == .collectingInputs else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "Participant reservation arrived out of order"
            )
        }
        if let commitmentsDeadline = round.deadlines.commitmentsDeadline,
           now > commitmentsDeadline {
            return failRound(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: "Commitment deadline elapsed before PlayerCommit submission"
            )
        }

        round.participantReservation = reservation
        let commit: OpalFusion.ProtocolModel.PlayerCommit
        do {
            commit = try workflow.buildPlayerCommit(&round)
        } catch {
            return failForWorkflowFailure(error)
        }
        round.playerCommit = commit
        round.substate = .awaitingBlindSignatures
        self.round = round

        return [
            .sendPrimary(.playerCommit(commit)),
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .awaitingBlindSignatures,
                summary: "Submitting player commitments and blind requests"
            )
        ]
    }

    mutating func handleFinalizedTransactionLoaded(
        _ transaction: OpalFusion.Host.FinalizedTransaction,
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if round?.substate == .terminal {
            return []
        }

        guard var round, round.substate == .awaitingHostFinalization else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "Finalized transaction arrived out of order"
            )
        }

        if let conclusionTimeout = round.deadlines.conclusionTimeout,
           now > conclusionTimeout {
            return failRound(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: "Round conclusion timeout elapsed"
            )
        }

        if let signaturesDeadline = round.deadlines.signaturesDeadline,
           now > signaturesDeadline {
            return failRound(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: "Signature deadline elapsed before submission"
            )
        }

        round.finalizedTransaction = transaction
        do {
            _ = try workflow.buildCovertSignatureMessages(&round)
        } catch {
            recordTransactionSignatureMaterialFailure(
                error,
                roundIdentifier: round.identifier
            )
            return failForWorkflowFailure(error)
        }
        round.substate = .awaitingSignatureWindow
        self.round = round
        OpalDiagnostics.logger(category: .fusionTransaction).record(
            event: .transactionFinalizationSucceeded,
            level: .opalFusionDefault(for: .transactionFinalizationSucceeded),
            traceID: .opalFusionRound(round.identifier),
            fields: [
                .operation("transaction_finalization"),
                .phase(.assemblingTransaction),
                .roundState(round.substate)
            ]
        )

        var effects = [
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .assemblingTransaction,
                summary: "Transaction finalized; waiting for signature window"
            )
        ]
        effects.append(contentsOf: maybeOpenSignatureSubmission(now: now))
        return effects
    }

    mutating func handleClockAdvanced(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        if let timeoutEffects = timeoutEffectsIfNeeded(now: now), timeoutEffects.isEmpty == false {
            return timeoutEffects
        }

        var effects = covertCloseEffectsIfNeeded(now: now)
        effects.append(contentsOf: maybeOpenCovertSubmission(now: now))
        effects.append(contentsOf: maybeOpenSignatureSubmission(now: now))
        return effects
    }
}
