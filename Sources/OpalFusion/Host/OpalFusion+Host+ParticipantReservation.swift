// OpalFusion+Host+ParticipantReservation.swift

public extension OpalFusion.Host {
    struct ParticipantReservation: Sendable, Equatable {
        public let inputs: [OpalFusion.Host.ParticipantInput]
        public let outputs: [OpalFusion.Host.ParticipantOutput]

        public init(
            inputs: [OpalFusion.Host.ParticipantInput],
            outputs: [OpalFusion.Host.ParticipantOutput]
        ) {
            self.inputs = inputs
            self.outputs = outputs
        }
    }
}
