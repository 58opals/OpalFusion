// OpalFusion+Mosaic+NostrNamespace+EventCodec~Validation.swift

import Foundation

extension OpalFusion.Mosaic.NostrNamespace.EventCodec {
    static func validate(
        tags: [[String]],
        content: String,
        limits: OpalFusion.Mosaic.NostrNamespace.EventCodingLimits
    ) throws {
        guard tags.count <= limits.maximumTagCount else {
            throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .tagCountExceedsMaximum(
                    maximum: limits.maximumTagCount,
                    actual: tags.count
                )
        }
        try validateString(content, limits: limits)
        for (tagIndex, tag) in tags.enumerated() {
            guard !tag.isEmpty else {
                throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                    .emptyTag(index: tagIndex)
            }
            guard tag.count <= limits.maximumTagElementCount else {
                throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
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
        limits: OpalFusion.Mosaic.NostrNamespace.EventCodingLimits
    ) throws {
        guard actual <= limits.maximumEventJSONByteCount else {
            throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .eventJSONByteCountExceedsMaximum(
                    maximum: limits.maximumEventJSONByteCount,
                    actual: actual
                )
        }
    }

    private static func validateString(
        _ value: String,
        limits: OpalFusion.Mosaic.NostrNamespace.EventCodingLimits
    ) throws {
        let actual = value.utf8.count
        guard actual <= limits.maximumStringByteCount else {
            throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .stringByteCountExceedsMaximum(
                    maximum: limits.maximumStringByteCount,
                    actual: actual
                )
        }
    }
}
