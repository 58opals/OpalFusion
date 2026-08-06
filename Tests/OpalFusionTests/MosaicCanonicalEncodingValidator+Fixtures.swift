// MosaicCanonicalEncodingValidator+Fixtures.swift

@testable import OpalFusion
import Testing

extension MosaicCanonicalEncodingValidator {
    typealias CanonicalEncoder = OpalFusion.Mosaic.CanonicalEncoder
    typealias CanonicalDecoder = OpalFusion.Mosaic.CanonicalDecoder
    typealias CanonicalCodingError = OpalFusion.Mosaic.CanonicalCodingError

    static func encode(
        _ writeValue: (inout CanonicalEncoder) throws -> Void
    ) rethrows -> [UInt8] {
        var encoder = CanonicalEncoder()
        try writeValue(&encoder)
        return encoder.encodedBytes
    }

    static func expectCodingError<Value>(
        _ expectedError: CanonicalCodingError,
        from operation: () throws -> Value
    ) {
        #expect(throws: expectedError) {
            _ = try operation()
        }
    }

    static func makeLengthPrefix(for byteCount: Int) -> [UInt8] {
        let count = UInt32(byteCount)
        return [
            UInt8(truncatingIfNeeded: count >> 24),
            UInt8(truncatingIfNeeded: count >> 16),
            UInt8(truncatingIfNeeded: count >> 8),
            UInt8(truncatingIfNeeded: count)
        ]
    }
}
