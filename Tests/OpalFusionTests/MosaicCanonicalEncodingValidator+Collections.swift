// MosaicCanonicalEncodingValidator+Collections.swift

@testable import OpalFusion
import Testing

extension MosaicCanonicalEncodingValidator {
    @Test("Canonical empty collections contain only their zero counts")
    func validateEmptyCollectionEncoding() throws {
        let encoded = try Self.encode { encoder in
            try encoder.writeVector([UInt8]()) { nestedEncoder, value in
                nestedEncoder.writeUInt8(value)
            }
            try encoder.writeSortedSet([UInt8]()) { nestedEncoder, value in
                nestedEncoder.writeUInt8(value)
            }
        }
        #expect(encoded == [UInt8](repeating: 0x00, count: 8))

        let decodedCounts = try CanonicalDecoder.decode(from: encoded) { decoder in
            let vector = try decoder.readVector { try $0.readUInt8() }
            let sortedSet = try decoder.readSortedSet { try $0.readUInt8() }
            return [vector.count, sortedSet.count]
        }
        #expect(decodedCounts == [0, 0])
    }

    @Test("Canonical vectors preserve item order after a UInt32 count")
    func validateVectorEncoding() throws {
        let values: [UInt16] = [0x0102, 0xA0B0]
        let encoded = try Self.encode { encoder in
            try encoder.writeVector(values) { nestedEncoder, value in
                nestedEncoder.writeUInt16(value)
            }
        }
        #expect(encoded == [
            0x00, 0x00, 0x00, 0x02,
            0x01, 0x02,
            0xA0, 0xB0
        ])

        let decoded = try CanonicalDecoder.decode(from: encoded) { decoder in
            try decoder.readVector { try $0.readUInt16() }
        }
        #expect(decoded == values)
    }

    @Test("Canonical sets sort by each member's complete encoded bytes")
    func validateSortedSetEncoding() throws {
        let encoded = try Self.encode { encoder in
            try encoder.writeSortedSet(["aa", "z"]) { nestedEncoder, value in
                try nestedEncoder.writeText(value)
            }
        }
        let expected: [UInt8] = [
            0x00, 0x00, 0x00, 0x02,
            0x00, 0x00, 0x00, 0x01, 0x7A,
            0x00, 0x00, 0x00, 0x02, 0x61, 0x61
        ]
        #expect(encoded == expected)

        let decoded = try CanonicalDecoder.decode(from: encoded) { decoder in
            try decoder.readSortedSet { try $0.readText() }
        }
        #expect(decoded == ["z", "aa"])
    }

    @Test("Canonical set encoders reject duplicate member encodings")
    func validateDuplicateSetEncodingRejection() {
        Self.expectCodingError(.duplicateSetMember) {
            try Self.encode { encoder in
                try encoder.writeSortedSet([UInt8(1), UInt8(1)]) {
                    nestedEncoder,
                    value in
                    nestedEncoder.writeUInt8(value)
                }
            }
        }
    }
}
