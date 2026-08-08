// OpalFusion+Mosaic+RuntimeSessionDriver+InitializationError.swift

extension OpalFusion.Mosaic.RuntimeSessionDriver {
    enum InitializationError: Error, Sendable, Equatable {
        case unsupportedProfile(OpalFusion.Mosaic.Profile)
        case terminalSession(OpalFusion.Mosaic.Attempt.Outcome)
    }
}
