// OpalFusion+Mosaic+NostrNamespace+EventCodec~Decoding.swift

import Foundation

extension OpalFusion.Mosaic.NostrNamespace.EventCodec {
    private static let expectedTopLevelFields: Set<String> = [
        "id", "pubkey", "created_at", "kind", "tags", "content", "sig"
    ]

    static func decodeHexadecimal(
        _ value: String,
        field: String
    ) throws -> Data {
        guard value.utf8.count.isMultiple(of: 2),
              value.utf8.allSatisfy({ byte in
                  (0x30 ... 0x39).contains(byte)
                      || (0x61 ... 0x66).contains(byte)
              }) else {
            throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .invalidHexadecimal(field: field)
        }
        let bytes = Array(value.utf8)
        var result = Data()
        result.reserveCapacity(bytes.count / 2)
        for offset in stride(from: 0, to: bytes.count, by: 2) {
            result.append((nibble(bytes[offset]) << 4) | nibble(bytes[offset + 1]))
        }
        return result
    }

    static func validateTopLevelFields(in data: Data) throws {
        let fields = try OpalFusion.Mosaic.NostrNamespace.TopLevelFieldScanner.fields(
            in: data
        )
        var found = Set<String>()
        for field in fields {
            guard expectedTopLevelFields.contains(field) else {
                throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                    .unexpectedTopLevelField(field)
            }
            guard found.insert(field).inserted else {
                throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                    .duplicateTopLevelField(field)
            }
        }
        for field in expectedTopLevelFields where !found.contains(field) {
            throw OpalFusion.Mosaic.NostrNamespace.EventCodingError
                .missingTopLevelField(field)
        }
    }

    private static func nibble(_ byte: UInt8) -> UInt8 {
        byte <= 0x39 ? byte - 0x30 : byte - 0x61 + 10
    }

}
