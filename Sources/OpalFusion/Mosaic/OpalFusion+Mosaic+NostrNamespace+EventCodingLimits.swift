// OpalFusion+Mosaic+NostrNamespace+EventCodingLimits.swift

extension OpalFusion.Mosaic.NostrNamespace {
    /// Caller-owned parser limits that do not define Mosaic wire constants.
    struct EventCodingLimits: Sendable, Equatable {
        let maximumEventJSONByteCount: Int
        let maximumTagCount: Int
        let maximumTagElementCount: Int
        let maximumStringByteCount: Int

        init(
            maximumEventJSONByteCount: Int,
            maximumTagCount: Int,
            maximumTagElementCount: Int,
            maximumStringByteCount: Int
        ) throws {
            guard maximumEventJSONByteCount > 0,
                  maximumTagCount >= 0,
                  maximumTagElementCount > 0,
                  maximumStringByteCount > 0 else {
                throw EventCodingError.invalidResourceLimit
            }
            self.maximumEventJSONByteCount = maximumEventJSONByteCount
            self.maximumTagCount = maximumTagCount
            self.maximumTagElementCount = maximumTagElementCount
            self.maximumStringByteCount = maximumStringByteCount
        }
    }
}
