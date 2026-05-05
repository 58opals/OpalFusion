// OpalFusion+Execution+RoundSubstate.swift

import OpalCrypto

extension OpalFusion.Execution {
    enum RoundSubstate: String, Sendable, Equatable {
        case warmup
        case collectingInputs
        case awaitingBlindSignatures
        case awaitingAllCommitments
        case awaitingCovertComponentWindow
        case submittingCovertComponents
        case awaitingSharedComponents
        case awaitingHostFinalization
        case awaitingSignatureWindow
        case submittingSignatures
        case awaitingResult
        case awaitingTheirProofs
        case submittingBlames
        case awaitingRestart
        case terminal
    }
}
