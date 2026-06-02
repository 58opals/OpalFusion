// OpalFusion+Execution+RoundContext.swift

import OpalCrypto

extension OpalFusion.Execution {
    struct RoundContext: Sendable {
        let fusionBegin: OpalFusion.ProtocolModel.FusionBegin
        let serverHello: OpalFusion.ProtocolModel.ServerHello
        var startRound: OpalFusion.ProtocolModel.StartRound?
        var identifier: OpalFusion.Round.Identifier?
        var participantReservation: OpalFusion.Host.ParticipantReservation?
        var playerCommit: OpalFusion.ProtocolModel.PlayerCommit?
        var blindSignatureResponses: OpalFusion.ProtocolModel.BlindSignatureResponses?
        var allCommitments: OpalFusion.ProtocolModel.AllCommitments?
        var sharedComponents: OpalFusion.ProtocolModel.ShareCovertComponents?
        var finalizedTransaction: OpalFusion.Host.FinalizedTransaction?
        var fusionResult: OpalFusion.ProtocolModel.FusionResult?
        var myProofsList: OpalFusion.ProtocolModel.MyProofsList?
        var theirProofsList: OpalFusion.ProtocolModel.TheirProofsList?
        var blames: OpalFusion.ProtocolModel.Blames?
        var substate: OpalFusion.Execution.RoundSubstate
        var deadlines: OpalFusion.Execution.Deadlines
        var hasStartedCovertClose: Bool
        var completionStatus: OpalFusion.Round.CompletionStatus?
        var executionMaterial: OpalFusion.Execution.ExecutionMaterial

        init(
            fusionBegin: OpalFusion.ProtocolModel.FusionBegin,
            serverHello: OpalFusion.ProtocolModel.ServerHello,
            deadlines: OpalFusion.Execution.Deadlines
        ) {
            self.fusionBegin = fusionBegin
            self.serverHello = serverHello
            self.startRound = nil
            self.identifier = nil
            self.participantReservation = nil
            self.playerCommit = nil
            self.blindSignatureResponses = nil
            self.allCommitments = nil
            self.sharedComponents = nil
            self.finalizedTransaction = nil
            self.fusionResult = nil
            self.myProofsList = nil
            self.theirProofsList = nil
            self.blames = nil
            self.substate = .warmup
            self.deadlines = deadlines
            self.hasStartedCovertClose = false
            self.completionStatus = nil
            self.executionMaterial = .init()
        }
    }
}
