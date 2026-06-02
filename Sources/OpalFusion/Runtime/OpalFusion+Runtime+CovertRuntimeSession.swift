// OpalFusion+Runtime+CovertRuntimeSession.swift

import OpalDiagnostics

extension OpalFusion.Runtime {
    struct CovertRuntimeSession: Sendable {
        var endpointContext: OpalFusion.Runtime.CovertEndpointContext?
        var substate: OpalFusion.Runtime.CovertRuntimeSubstate
        var preparationPlan: OpalFusion.Runtime.CovertPreparationPlan?
        var queuedMessages: [OpalFusion.ProtocolModel.CovertMessage]
        var outstandingRequest: OpalFusion.Runtime.CovertRequest?
        var roundIdentifier: OpalFusion.Round.Identifier?
        var submitWindowDeadline: OpalFusion.Execution.Instant?
        let messageEncoder: OpalFusion.Wire.CovertMessageEncoder
        let messageDecoder: OpalFusion.Wire.CovertMessageDecoder

        init() {
            self.endpointContext = nil
            self.substate = .idle
            self.preparationPlan = nil
            self.queuedMessages = []
            self.outstandingRequest = nil
            self.roundIdentifier = nil
            self.submitWindowDeadline = nil
            self.messageEncoder = .init()
            self.messageDecoder = .init()
        }









        var currentRoundTraceIdentifier: OpalFusion.Round.Identifier? {
            roundIdentifier ?? endpointContext?.roundIdentifier
        }






    }
}
