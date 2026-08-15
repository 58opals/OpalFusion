// OpalFusion+Mosaic+CanonicalDecoder.swift

extension OpalFusion.Mosaic {
    struct CanonicalDecoder: Sendable {
        private let bytes: [UInt8]
        private var cursor: Int

        private init(encodedBytes: [UInt8]) {
            self.bytes = encodedBytes
            self.cursor = 0
        }

        static func decode<Value>(
            from encodedBytes: [UInt8],
            readingValueWith readValue: (inout Self) throws -> Value
        ) throws -> Value {
            var decoder = Self(encodedBytes: encodedBytes)
            let value = try readValue(&decoder)
            guard decoder.remainingByteCount == 0 else {
                throw CanonicalCodingError.trailingBytes(
                    decoder.remainingByteCount
                )
            }
            return value
        }

        mutating func readUInt8() throws -> UInt8 {
            try readRawBytes(byteCount: 1)[0]
        }

        mutating func readUInt16() throws -> UInt16 {
            try readRawBytes(byteCount: 2).reduce(UInt16.zero) {
                ($0 << 8) | UInt16($1)
            }
        }

        mutating func readUInt32() throws -> UInt32 {
            try readRawBytes(byteCount: 4).reduce(UInt32.zero) {
                ($0 << 8) | UInt32($1)
            }
        }

        mutating func readUInt64() throws -> UInt64 {
            try readRawBytes(byteCount: 8).reduce(UInt64.zero) {
                ($0 << 8) | UInt64($1)
            }
        }

        mutating func readBool() throws -> Bool {
            let encodedBool = try readUInt8()
            switch encodedBool {
            case 0x00:
                return false
            case 0x01:
                return true
            default:
                throw CanonicalCodingError.invalidBoolean(encodedBool)
            }
        }

        mutating func readFixedBytes(byteCount: Int) throws -> [UInt8] {
            try readRawBytes(byteCount: byteCount)
        }

        mutating func readBytes() throws -> [UInt8] {
            let byteCount = Int(try readUInt32())
            return try readRawBytes(byteCount: byteCount)
        }

        mutating func readBytes(
            maximumByteCount: Int
        ) throws -> [UInt8] {
            let byteCount = Int(try readUInt32())
            guard byteCount <= maximumByteCount else {
                throw CanonicalCodingError.lengthLimitExceeded(
                    maximum: maximumByteCount,
                    actual: byteCount
                )
            }
            return try readRawBytes(byteCount: byteCount)
        }

        mutating func readText() throws -> String {
            let encodedText = try readBytes()
            return try decodeText(encodedText)
        }

        mutating func readText(
            maximumByteCount: Int
        ) throws -> String {
            let encodedText = try readBytes(
                maximumByteCount: maximumByteCount
            )
            return try decodeText(encodedText)
        }

        private func decodeText(_ encodedText: [UInt8]) throws -> String {
            let text = String(decoding: encodedText, as: UTF8.self)
            guard text.utf8.elementsEqual(encodedText) else {
                throw CanonicalCodingError.invalidUTF8Text
            }
            guard encodedText.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else {
                throw CanonicalCodingError.nonPrintableASCIIText
            }
            return text
        }

        mutating func readOptional<Value>(
            readingValueWith readValue: (inout Self) throws -> Value
        ) throws -> Value? {
            guard try readBool() else {
                return nil
            }
            return try readValue(&self)
        }

        mutating func readVector<Value>(
            readingValueWith readValue: (inout Self) throws -> Value
        ) throws -> [Value] {
            let count = try readCollectionCount()
            return try readVector(count: count, readingValueWith: readValue)
        }

        mutating func readVector<Value>(
            maximumCount: Int,
            readingValueWith readValue: (inout Self) throws -> Value
        ) throws -> [Value] {
            let count = try readCollectionCount()
            guard count <= maximumCount else {
                throw CanonicalCodingError.lengthLimitExceeded(
                    maximum: maximumCount,
                    actual: count
                )
            }
            return try readVector(count: count, readingValueWith: readValue)
        }

        private mutating func readVector<Value>(
            count: Int,
            readingValueWith readValue: (inout Self) throws -> Value
        ) throws -> [Value] {
            var values: [Value] = []
            for _ in 0 ..< count {
                values.append(try readValue(&self))
            }
            return values
        }

        mutating func readSortedSet<Value>(
            readingValueWith readValue: (inout Self) throws -> Value
        ) throws -> [Value] {
            let count = try readCollectionCount()
            var values: [Value] = []
            var previousMemberBytes: [UInt8]?

            for _ in 0 ..< count {
                let memberStart = cursor
                let value = try readValue(&self)
                let memberBytes = Array(bytes[memberStart ..< cursor])

                if let previousMemberBytes {
                    guard previousMemberBytes != memberBytes else {
                        throw CanonicalCodingError.duplicateSetMember
                    }
                    guard previousMemberBytes.lexicographicallyPrecedes(memberBytes) else {
                        throw CanonicalCodingError.nonCanonicalSetOrdering
                    }
                }

                values.append(value)
                previousMemberBytes = memberBytes
            }

            return values
        }

        private var remainingByteCount: Int {
            bytes.count - cursor
        }

        private mutating func readCollectionCount() throws -> Int {
            let count = Int(try readUInt32())
            guard count <= remainingByteCount else {
                throw CanonicalCodingError.truncatedInput(
                    expectedByteCount: count,
                    remainingByteCount: remainingByteCount
                )
            }
            return count
        }

        private mutating func readRawBytes(byteCount: Int) throws -> [UInt8] {
            guard byteCount <= remainingByteCount else {
                throw CanonicalCodingError.truncatedInput(
                    expectedByteCount: byteCount,
                    remainingByteCount: remainingByteCount
                )
            }

            let result = Array(bytes[cursor ..< cursor + byteCount])
            cursor += byteCount
            return result
        }
    }
}
