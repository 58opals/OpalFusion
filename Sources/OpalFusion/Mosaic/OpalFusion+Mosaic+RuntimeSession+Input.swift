// OpalFusion+Mosaic+RuntimeSession+Input.swift

extension OpalFusion.Mosaic.RuntimeSession {
    enum Input: Sendable, Equatable {
        case local(LocalOperation)
        case hostResult(HostResult)
        case authenticated(AuthenticatedMessage)
    }

}
