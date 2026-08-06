// MosaicCanonicalEncodingValidator+Primitives.swift

@testable import OpalFusion
import Testing

extension MosaicCanonicalEncodingValidator {
    @Test("Canonical unsigned integers use their fixed big-endian widths")
    func validateUnsignedIntegerEncoding() throws {
        let encoded = Self.encode { encoder in
            encoder.writeUInt8(0xAB)
            encoder.writeUInt16(0x0102)
            encoder.writeUInt32(0x03040506)
            encoder.writeUInt64(0x0708090A0B0C0D0E)
        }

        #expect(encoded == [
            0xAB,
            0x01, 0x02,
            0x03, 0x04, 0x05, 0x06,
            0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E
        ])

        let decoded = try CanonicalDecoder.decode(from: encoded) { decoder in
            [
                UInt64(try decoder.readUInt8()),
                UInt64(try decoder.readUInt16()),
                UInt64(try decoder.readUInt32()),
                try decoder.readUInt64()
            ]
        }
        #expect(decoded == [
            0xAB,
            0x0102,
            0x03040506,
            0x0708090A0B0C0D0E
        ])
    }

    @Test("Canonical booleans use only zero and one")
    func validateBooleanEncoding() throws {
        let encoded = Self.encode { encoder in
            encoder.writeBool(false)
            encoder.writeBool(true)
        }
        #expect(encoded == [0x00, 0x01])

        let decoded = try CanonicalDecoder.decode(from: encoded) { decoder in
            [try decoder.readBool(), try decoder.readBool()]
        }
        #expect(decoded == [false, true])
    }

    @Test(
        "Byte strings use UInt32 length prefixes at compact boundaries",
        arguments: [0, 1, 255, 256]
    )
    func validateByteLengthPrefixes(byteCount: Int) throws {
        let value = [UInt8](repeating: 0xA5, count: byteCount)
        let encoded = try Self.encode { encoder in
            try encoder.writeBytes(value)
        }

        #expect(encoded == Self.makeLengthPrefix(for: byteCount) + value)
        #expect(
            try CanonicalDecoder.decode(from: encoded) { decoder in
                try decoder.readBytes()
            } == value
        )
    }

    @Test("Protocol text is encoded as printable ASCII bytes")
    func validateProtocolTextEncoding() throws {
        let value = "Mosaic/1-draft.1"
        let encoded = try Self.encode { encoder in
            try encoder.writeText(value)
        }

        #expect(encoded == Self.makeLengthPrefix(for: value.utf8.count) + value.utf8)
        #expect(
            try CanonicalDecoder.decode(from: encoded) { decoder in
                try decoder.readText()
            } == value
        )
    }

    @Test("Canonical optionals use an explicit presence byte")
    func validateOptionalEncoding() throws {
        let absent: UInt16? = nil
        let present: UInt16? = 0x1234
        let encoded = Self.encode { encoder in
            encoder.writeOptional(absent) { nestedEncoder, value in
                nestedEncoder.writeUInt16(value)
            }
            encoder.writeOptional(present) { nestedEncoder, value in
                nestedEncoder.writeUInt16(value)
            }
        }
        #expect(encoded == [0x00, 0x01, 0x12, 0x34])

        let decoded = try CanonicalDecoder.decode(from: encoded) { decoder in
            [
                try decoder.readOptional { try $0.readUInt16() },
                try decoder.readOptional { try $0.readUInt16() }
            ]
        }
        #expect(decoded == [nil, 0x1234])
    }
}
