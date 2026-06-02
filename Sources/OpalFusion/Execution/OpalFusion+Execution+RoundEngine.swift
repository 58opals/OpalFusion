// OpalFusion+Execution+RoundEngine.swift

import Foundation
import OpalDiagnostics

extension OpalFusion.Execution {
    struct RoundEngine: Sendable {
        var session: OpalFusion.Execution.SessionContext
        var round: OpalFusion.Execution.RoundContext?
        let workflow: OpalFusion.Execution.WorkflowContext

        init(
            configuration: OpalFusion.Client.Configuration,
            genesisHash: [UInt8]? = nil,
            joinPools: OpalFusion.ProtocolModel.JoinPools,
            workflow: OpalFusion.Execution.WorkflowContext,
            baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
        ) {
            self.session = .init(
                configuration: configuration,
                baseline: baseline,
                genesisHash: genesisHash,
                joinPools: joinPools
            )
            self.round = nil
            self.workflow = workflow
        }

        var clientState: OpalFusion.Client.State {
            .init(
                isConnected: session.isConnected,
                round: projectedRoundState
            )
        }


        var projectedRoundState: OpalFusion.Round.State? {
            guard let round, let identifier = round.identifier else {
                return nil
            }

            let phase: OpalFusion.Round.Phase
            switch round.substate {
            case .warmup:
                phase = .connecting
            case .collectingInputs:
                phase = .registeringInputs
            case .awaitingBlindSignatures:
                phase = .awaitingBlindSignatures
            case .awaitingAllCommitments, .awaitingCovertComponentWindow, .submittingCovertComponents:
                phase = .awaitingCommitments
            case .awaitingSharedComponents, .awaitingHostFinalization, .awaitingSignatureWindow,
                    .submittingSignatures, .awaitingResult:
                phase = .assemblingTransaction
            case .awaitingTheirProofs, .submittingBlames, .awaitingRestart:
                phase = .blame
            case .terminal:
                phase = .completed
            }

            let completionStatus = round.completionStatus

            if let completionStatus {
                return .init(
                    identifier: identifier,
                    participantCount: nil,
                    completionStatus: completionStatus
                )
            }

            return .init(
                identifier: identifier,
                phase: phase,
                participantCount: nil
            )
        }






























    }
}
