// OpalFusion+Mosaic+RuntimeSessionDriver+State.swift

extension OpalFusion.Mosaic.RuntimeSessionDriver {
    enum State: Sendable, Equatable {
        case idle
        case running(phase: OpalFusion.Mosaic.Attempt.Phase)
        case terminal(OpalFusion.Mosaic.Attempt.Outcome)

    }
}
