// OpalFusion+Execution+RoundEngine+ImplementationGroup4.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution.RoundEngine {
    mutating func covertCloseEffectsIfNeeded(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard var round,
              round.hasStartedCovertClose == false,
              let closeStart = round.deadlines.closeStart,
              now >= closeStart else {
            return []
        }

        switch round.substate {
        case .awaitingTheirProofs, .submittingBlames, .awaitingRestart, .terminal:
            return []
        case .warmup, .collectingInputs, .awaitingBlindSignatures, .awaitingAllCommitments,
                .awaitingCovertComponentWindow, .submittingCovertComponents,
                .awaitingSharedComponents, .awaitingHostFinalization,
                .awaitingSignatureWindow, .submittingSignatures, .awaitingResult:
            round.hasStartedCovertClose = true
            self.round = round
            return [.resetCovertTransport]
        }
    }

    mutating func maybeOpenCovertSubmission(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard var round,
              round.substate == .awaitingCovertComponentWindow,
              let covertComponentsStart = round.deadlines.covertComponentsStart,
              let covertComponentsDeadline = round.deadlines.covertComponentsDeadline,
              now >= covertComponentsStart else {
            return []
        }

        guard now <= covertComponentsDeadline else {
            return failRound(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: "Covert component deadline elapsed before submission"
            )
        }

        let messages: [OpalFusion.ProtocolModel.CovertMessage]
        do {
            messages = try workflow.buildCovertComponentMessages(&round)
        } catch {
            OpalDiagnostics.logger(category: .fusionCovert).record(
                event: .covertMessageEncodeFailed,
                level: .opalFusionDefault(for: .covertMessageEncodeFailed),
                traceID: .opalFusionRound(round.identifier),
                fields: [
                    .operation("covert_component_material")
                ] + OpalDiagnostics.Field.errorFields(for: error)
            )
            return failForWorkflowFailure(error)
        }
        round.substate = .submittingCovertComponents
        self.round = round

        var effects = messages.map(OpalFusion.Execution.RoundEngine.Effect.submitCovert)
        effects.append(
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .awaitingCommitments,
                summary: "Submitting covert components"
            )
        )
        return effects
    }

    mutating func maybeOpenSignatureSubmission(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard var round,
              round.substate == .awaitingSignatureWindow,
              let signaturesStart = round.deadlines.signaturesStart,
              let signaturesDeadline = round.deadlines.signaturesDeadline,
              now >= signaturesStart else {
            return []
        }

        guard now <= signaturesDeadline else {
            return failRound(
                completionStatus: .transportFailed,
                clientError: .transportUnavailable,
                summary: "Signature deadline elapsed before submission"
            )
        }

        let messages: [OpalFusion.ProtocolModel.CovertMessage]
        do {
            messages = try workflow.buildCovertSignatureMessages(&round)
        } catch {
            recordTransactionSignatureMaterialFailure(
                error,
                roundIdentifier: round.identifier
            )
            return failForWorkflowFailure(error)
        }
        round.substate = .submittingSignatures
        self.round = round

        var effects = messages.map(OpalFusion.Execution.RoundEngine.Effect.submitCovert)
        effects.append(
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .assemblingTransaction,
                summary: "Submitting covert transaction signatures"
            )
        )
        return effects
    }

    mutating func timeoutEffectsIfNeeded(
        now: OpalFusion.Execution.Instant
    ) -> [OpalFusion.Execution.RoundEngine.Effect]? {
        guard let round else {
            return nil
        }

        switch round.substate {
        case .warmup:
            if now > round.deadlines.warmupDeadline {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Warmup expired before StartRound arrived"
                )
            }
        case .collectingInputs:
            if let commitmentsDeadline = round.deadlines.commitmentsDeadline,
               now > commitmentsDeadline {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Commitment deadline elapsed before PlayerCommit submission"
                )
            }
        case .awaitingBlindSignatures, .awaitingAllCommitments, .awaitingCovertComponentWindow:
            if let covertComponentsDeadline = round.deadlines.covertComponentsDeadline,
               now > covertComponentsDeadline {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Round expired before covert component submission completed"
                )
            }
        case .submittingCovertComponents, .awaitingSharedComponents, .awaitingHostFinalization,
                .awaitingSignatureWindow, .submittingSignatures, .awaitingResult:
            if let conclusionTimeout = round.deadlines.conclusionTimeout,
               now > conclusionTimeout {
                return failRound(
                    completionStatus: .transportFailed,
                    clientError: .transportUnavailable,
                    summary: "Round conclusion timeout elapsed"
                )
            }
        case .awaitingTheirProofs, .submittingBlames, .awaitingRestart:
            if let blameVerifyDeadline = round.deadlines.blameVerifyDeadline,
               now > blameVerifyDeadline {
                return failRound(
                    completionStatus: .blameRequired,
                    clientError: .blameRequired,
                    summary: "Blame handling did not complete"
                )
            }
        case .terminal:
            return nil
        }

        return nil
    }
}
