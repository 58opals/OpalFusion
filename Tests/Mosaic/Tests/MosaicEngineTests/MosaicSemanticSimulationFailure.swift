// MosaicSemanticSimulationFailure.swift

enum MosaicSemanticSimulationFailure: Error, Equatable {
    case attemptNotReady
    case materialIdentifierCountMismatch(expected: Int, actual: Int)
}
