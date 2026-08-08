// OpalFusion+Mosaic+RuntimeSession+Failure.swift

extension OpalFusion.Mosaic.RuntimeSession {
    enum Failure: Swift.Error, Sendable, Equatable {
        case attemptNotReady
        case attemptIdentifierMismatch
        case generationIdentifierMismatch
        case senderNotInRoster
        case staleSequence(greatestAccepted: UInt64, received: UInt64)
        case sequenceConflict
        case phaseMismatch
        case invalidManifestSignatureCount(expected: Int, actual: Int)
        case invalidManifestSignature(
            OpalFusion.Mosaic.Attempt.ManifestSignatureValidation.ValidationError
        )
    }
}
