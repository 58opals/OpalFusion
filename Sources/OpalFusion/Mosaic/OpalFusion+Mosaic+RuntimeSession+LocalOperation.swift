// OpalFusion+Mosaic+RuntimeSession+LocalOperation.swift

extension OpalFusion.Mosaic.RuntimeSession {
    enum LocalOperation: Sendable, Equatable {
        case cancel
        case retryRequested
        case transcriptInclusionValidated(
            OpalFusion.Mosaic.LocalAttempt.TranscriptInclusionValidation
        )
    }
}
