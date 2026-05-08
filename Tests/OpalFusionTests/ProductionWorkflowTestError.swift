// ProductionWorkflowTestError.swift

enum ProductionWorkflowTestError: Swift.Error, Equatable {
    case expectedComponentMessage
    case missingParticipantInputPublicKey
    case participantPrivateKeyCountMismatch
    case signingInputNotFound
}
