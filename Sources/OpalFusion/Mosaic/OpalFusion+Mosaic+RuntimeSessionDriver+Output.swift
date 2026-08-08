// OpalFusion+Mosaic+RuntimeSessionDriver+Output.swift

extension OpalFusion.Mosaic.RuntimeSessionDriver {
    enum Output: Sendable, Equatable {
        case runtimeEffect(OpalFusion.Mosaic.RuntimeSession.Effect)
        case inputSourceTerminated(InputSourceTermination)
    }

    enum InputSourceTermination: Sendable, Equatable {
        case finished
        case failed
    }
}
