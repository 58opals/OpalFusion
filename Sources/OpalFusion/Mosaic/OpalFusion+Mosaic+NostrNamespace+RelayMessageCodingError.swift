// OpalFusion+Mosaic+NostrNamespace+RelayMessageCodingError.swift

extension OpalFusion.Mosaic.NostrNamespace {
    enum RelayMessageCodingError: Error, Sendable, Equatable {
        case invalidResourceLimit
        case frameByteCountExceedsMaximum(maximum: Int, actual: Int)
        case invalidJSON
        case invalidMessageShape
        case unsupportedMessageType(String)
        case invalidSubscriptionIdentifier
        case messageStringByteCountExceedsMaximum(maximum: Int, actual: Int)
        case emptyFilterSet
        case filterCountExceedsMaximum(maximum: Int, actual: Int)
        case filterValueCountExceedsMaximum(maximum: Int, actual: Int)
        case duplicateFilterValue(field: String)
        case invalidFilterTimeRange
        case invalidFilterLimit
        case invalidEventIdentifier
    }
}
