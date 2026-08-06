// MosaicCanonicalEncodingValidator+Failures.swift

@testable import OpalFusion
import Testing

extension MosaicCanonicalEncodingValidator {
    @Test(
        "Canonical decoders reject invalid boolean values",
        arguments: [UInt8(0x02), UInt8(0xFF)]
    )
    func validateInvalidBooleanRejection(encodedBool: UInt8) {
        Self.expectCodingError(.invalidBoolean(encodedBool)) {
            try CanonicalDecoder.decode(from: [encodedBool]) { decoder in
                try decoder.readBool()
            }
        }
    }

    @Test("Canonical decoders reject truncated fixed-width integers")
    func validateTruncatedIntegerRejection() {
        Self.expectCodingError(
            .truncatedInput(expectedByteCount: 1, remainingByteCount: 0)
        ) {
            try CanonicalDecoder.decode(from: []) { try $0.readUInt8() }
        }
        Self.expectCodingError(
            .truncatedInput(expectedByteCount: 2, remainingByteCount: 1)
        ) {
            try CanonicalDecoder.decode(from: [0x00]) { try $0.readUInt16() }
        }
        Self.expectCodingError(
            .truncatedInput(expectedByteCount: 4, remainingByteCount: 3)
        ) {
            try CanonicalDecoder.decode(from: [0x00, 0x00, 0x00]) {
                try $0.readUInt32()
            }
        }
        Self.expectCodingError(
            .truncatedInput(expectedByteCount: 8, remainingByteCount: 7)
        ) {
            try CanonicalDecoder.decode(from: [UInt8](repeating: 0x00, count: 7)) {
                try $0.readUInt64()
            }
        }
    }

    @Test("Canonical decoders reject truncated and maximum malformed byte lengths")
    func validateMalformedByteLengthRejection() {
        Self.expectCodingError(
            .truncatedInput(expectedByteCount: 4, remainingByteCount: 3)
        ) {
            try CanonicalDecoder.decode(from: [0x00, 0x00, 0x00]) {
                try $0.readBytes()
            }
        }
        Self.expectCodingError(
            .truncatedInput(expectedByteCount: 2, remainingByteCount: 1)
        ) {
            try CanonicalDecoder.decode(from: [0x00, 0x00, 0x00, 0x02, 0xAA]) {
                try $0.readBytes()
            }
        }
        Self.expectCodingError(
            .truncatedInput(
                expectedByteCount: Int(UInt32.max),
                remainingByteCount: 0
            )
        ) {
            try CanonicalDecoder.decode(from: [0xFF, 0xFF, 0xFF, 0xFF]) {
                try $0.readBytes()
            }
        }
    }

    @Test("Canonical decoders reject malformed vector counts before iteration")
    func validateMalformedVectorCountRejection() {
        Self.expectCodingError(
            .truncatedInput(expectedByteCount: 2, remainingByteCount: 1)
        ) {
            try CanonicalDecoder.decode(
                from: [0x00, 0x00, 0x00, 0x02, 0xAA]
            ) { decoder in
                try decoder.readVector { try $0.readUInt8() }
            }
        }
        Self.expectCodingError(
            .truncatedInput(
                expectedByteCount: Int(UInt32.max),
                remainingByteCount: 0
            )
        ) {
            try CanonicalDecoder.decode(from: [0xFF, 0xFF, 0xFF, 0xFF]) { decoder in
                try decoder.readVector { try $0.readUInt8() }
            }
        }
    }

    @Test("Canonical protocol text rejects invalid UTF-8 and non-printable ASCII")
    func validateProtocolTextRejection() {
        Self.expectCodingError(.invalidUTF8Text) {
            try CanonicalDecoder.decode(from: [0x00, 0x00, 0x00, 0x01, 0xFF]) {
                try $0.readText()
            }
        }
        Self.expectCodingError(.nonPrintableASCIIText) {
            try CanonicalDecoder.decode(
                from: [0x00, 0x00, 0x00, 0x02, 0xC3, 0xA9]
            ) {
                try $0.readText()
            }
        }
        Self.expectCodingError(.nonPrintableASCIIText) {
            try Self.encode { encoder in
                try encoder.writeText("line\n")
            }
        }
        Self.expectCodingError(.nonPrintableASCIIText) {
            try Self.encode { encoder in
                try encoder.writeText("é")
            }
        }
    }

    @Test("Canonical optionals reject unknown presence values")
    func validateInvalidOptionalPresenceRejection() {
        Self.expectCodingError(.invalidBoolean(0x02)) {
            try CanonicalDecoder.decode(from: [0x02]) { decoder in
                try decoder.readOptional { try $0.readUInt8() }
            }
        }
    }

    @Test("Canonical set decoders reject duplicates and descending order")
    func validateNonCanonicalSetRejection() {
        Self.expectCodingError(.duplicateSetMember) {
            try CanonicalDecoder.decode(
                from: [0x00, 0x00, 0x00, 0x02, 0x01, 0x01]
            ) {
                try $0.readSortedSet { try $0.readUInt8() }
            }
        }
        Self.expectCodingError(.nonCanonicalSetOrdering) {
            try CanonicalDecoder.decode(
                from: [0x00, 0x00, 0x00, 0x02, 0x02, 0x01]
            ) {
                try $0.readSortedSet { try $0.readUInt8() }
            }
        }
    }

    @Test("Canonical decoders reject trailing bytes")
    func validateTrailingByteRejection() {
        Self.expectCodingError(.trailingBytes(1)) {
            try CanonicalDecoder.decode(from: [0x01, 0x02]) {
                try $0.readUInt8()
            }
        }
    }
}
