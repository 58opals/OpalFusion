// OpalFusion+Execution+RoundEngine+SharedComponentsMessage.swift

import Foundation

extension OpalFusion.Execution.RoundEngine {
    mutating func handleShareCovertComponents(
        _ sharedComponents: OpalFusion.ProtocolModel.ShareCovertComponents,
        round: inout OpalFusion.Execution.RoundContext
    ) -> [OpalFusion.Execution.RoundEngine.Effect] {
        guard round.substate == .submittingCovertComponents ||
                round.substate == .awaitingSharedComponents else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "Shared components arrived out of order"
            )
        }

        round.sharedComponents = sharedComponents

        if sharedComponents.skipSignatures == true {
            do {
                _ = try workflow.buildTransactionFinalizationProposal(&round)
            } catch {
                recordTransactionProposalFailure(
                    error,
                    roundIdentifier: round.identifier
                )
                return failForWorkflowFailure(error)
            }
            round.substate = .awaitingResult
            self.round = round
            return [
                hostEvent(
                    roundIdentifier: round.identifier,
                    kind: .warning,
                    phase: .assemblingTransaction,
                    summary: "Coordinator skipped signatures; awaiting result"
                )
            ]
        }

        let proposal: OpalFusion.Host.TransactionFinalizationProposal
        do {
            proposal = try workflow.buildTransactionFinalizationProposal(&round)
        } catch {
            recordTransactionProposalFailure(
                error,
                roundIdentifier: round.identifier
            )
            return failForWorkflowFailure(error)
        }
        round.substate = .awaitingHostFinalization
        self.round = round

        guard let roundIdentifier = round.identifier else {
            return failRound(
                completionStatus: .protocolIncompatible,
                clientError: .protocolIncompatible,
                summary: "Shared components arrived before round identifier"
            )
        }

        return [
            .requestTransactionFinalization(
                roundIdentifier: roundIdentifier,
                proposal: proposal
            ),
            hostEvent(
                roundIdentifier: round.identifier,
                kind: .status,
                phase: .assemblingTransaction,
                summary: "Shared components received; requesting transaction finalization"
            )
        ]
    }
}
