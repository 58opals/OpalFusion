// OpalFusion+Mosaic+NostrNamespace+RelayMessageCodingLimits.swift

extension OpalFusion.Mosaic.NostrNamespace {
    /// Caller-owned relay-frame limits; these values are not Mosaic wire constants.
    struct RelayMessageCodingLimits: Sendable, Equatable {
        let maximumFrameByteCount: Int
        let maximumFiltersPerRequest: Int
        let maximumValuesPerFilter: Int
        let maximumMessageStringByteCount: Int
        let event: EventCodingLimits

        init(
            maximumFrameByteCount: Int,
            maximumFiltersPerRequest: Int,
            maximumValuesPerFilter: Int,
            maximumMessageStringByteCount: Int,
            event: EventCodingLimits
        ) throws {
            guard maximumFrameByteCount > 0,
                  maximumFiltersPerRequest > 0,
                  maximumValuesPerFilter > 0,
                  maximumMessageStringByteCount > 0 else {
                throw RelayMessageCodingError.invalidResourceLimit
            }
            self.maximumFrameByteCount = maximumFrameByteCount
            self.maximumFiltersPerRequest = maximumFiltersPerRequest
            self.maximumValuesPerFilter = maximumValuesPerFilter
            self.maximumMessageStringByteCount = maximumMessageStringByteCount
            self.event = event
        }
    }
}
