// OpalFusion+Mosaic+Nostr+EventCodec~Validation.swift

import Foundation

extension OpalFusion.Mosaic.Nostr.EventCodec {
    static func validate(
        tags: [[String]],
        content: String,
        limits: OpalFusion.Mosaic.Nostr.EventCodingLimits
    ) throws {
        guard tags.count <= limits.maximumTagCount else {
            throw OpalFusion.Mosaic.Nostr.EventCodingError
                .tagCountExceedsMaximum(
                    maximum: limits.maximumTagCount,
                    actual: tags.count
                )
        }
        try validateString(content, limits: limits)
        for (tagIndex, tag) in tags.enumerated() {
            guard !tag.isEmpty else {
                throw OpalFusion.Mosaic.Nostr.EventCodingError
                    .emptyTag(index: tagIndex)
            }
            guard tag.count <= limits.maximumTagElementCount else {
                throw OpalFusion.Mosaic.Nostr.EventCodingError
                    .tagElementCountExceedsMaximum(
                        tagIndex: tagIndex,
                        maximum: limits.maximumTagElementCount,
                        actual: tag.count
                    )
            }
            for value in tag {
                try validateString(value, limits: limits)
            }
        }
    }

    static func validateJSONByteCount(
        _ actual: Int,
        limits: OpalFusion.Mosaic.Nostr.EventCodingLimits
    ) throws {
        guard actual <= limits.maximumEventJSONByteCount else {
            throw OpalFusion.Mosaic.Nostr.EventCodingError
                .eventJSONByteCountExceedsMaximum(
                    maximum: limits.maximumEventJSONByteCount,
                    actual: actual
                )
        }
    }

    private static func validateString(
        _ value: String,
        limits: OpalFusion.Mosaic.Nostr.EventCodingLimits
    ) throws {
        let actual = value.utf8.count
        guard actual <= limits.maximumStringByteCount else {
            throw OpalFusion.Mosaic.Nostr.EventCodingError
                .stringByteCountExceedsMaximum(
                    maximum: limits.maximumStringByteCount,
                    actual: actual
                )
        }
    }
}
