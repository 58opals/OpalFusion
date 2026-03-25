// OpalFusion+Round+Phase.swift

public extension OpalFusion.Round {
    enum Phase: String, Sendable, Equatable {
        case idle
        case connecting
        case registeringInputs
        case awaitingCommitments
        case awaitingBlindSignatures
        case assemblingTransaction
        case blame
        case completed
    }
}
