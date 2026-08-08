// OpalFusion+Mosaic+RuntimeSession+Effect.swift

extension OpalFusion.Mosaic.RuntimeSession {
    enum Effect: Sendable, Equatable {
        case localAttempt(OpalFusion.Mosaic.LocalAttempt.Effect)
        case exactDuplicateIgnored
        case authenticatedInputRejected(Failure)
        case hostResultRejected(Failure)
    }
}
