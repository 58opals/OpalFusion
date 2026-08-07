// OpalFusion+Mosaic+RuntimeSession+LocalOperation.swift

extension OpalFusion.Mosaic.RuntimeSession {
    enum LocalOperation: Sendable, Equatable {
        case cancel
        case retryRequested

        var attemptInput: OpalFusion.Mosaic.Attempt.Input {
            switch self {
            case .cancel: .cancel
            case .retryRequested: .retryRequested
            }
        }
    }
}
