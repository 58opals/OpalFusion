// OpalFusion+Execution+WorkflowContext+Production.swift

import Foundation
import OpalCrypto
import SwiftProtobuf

extension OpalFusion.Execution.WorkflowContext {
    static func production(
        baseline: OpalFusion.Transport.BaselineConfiguration = .electronCash443
    ) -> Self {
        let workflow = OpalFusion.Execution.ProductionWorkflow(
            baseline: baseline
        )
        return .init(
            buildPlayerCommit: { round in
                try workflow.buildPlayerCommit(round: &round)
            },
            buildCovertComponentMessages: { round in
                try workflow.buildCovertComponentMessages(round: &round)
            },
            buildTransactionFinalizationProposal: { round in
                try workflow.buildTransactionFinalizationProposal(round: &round)
            },
            buildCovertSignatureMessages: { round in
                try workflow.buildCovertSignatureMessages(round: &round)
            },
            buildMyProofsList: { round in
                try workflow.buildMyProofsList(round: &round)
            },
            buildBlames: { round in
                try workflow.buildBlames(round: &round)
            }
        )
    }
}
