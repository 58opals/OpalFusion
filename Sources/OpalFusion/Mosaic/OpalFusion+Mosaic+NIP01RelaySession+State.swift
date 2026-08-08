// OpalFusion+Mosaic+NIP01RelaySession+State.swift

extension OpalFusion.Mosaic.NIP01RelaySession {
    enum State: Sendable, Equatable {
        case idle
        case opening
        case running
        case terminal(Termination)
    }

    enum Termination: Sendable, Equatable {
        case stopped
        case inputEnded
        case failed(Failure)
    }
}
