// OpalFusion+Mosaic+RuntimeSession.MessageIdentifier+ValidationError.swift

extension OpalFusion.Mosaic.RuntimeSession.MessageIdentifier {
    enum ValidationError: Swift.Error, Sendable, Equatable {
        case invalidByteCount(actual: Int)
    }
}
