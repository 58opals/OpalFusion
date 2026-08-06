// OpalFusion+Mosaic+CanonicalEncoder.swift

extension OpalFusion.Mosaic {
    struct CanonicalEncoder: Sendable {
        private var bytes: [UInt8] = []

        var encodedBytes: [UInt8] {
            bytes
        }

        mutating func writeUInt8(_ value: UInt8) {
            bytes.append(value)
        }

        mutating func writeUInt16(_ value: UInt16) {
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
            bytes.append(UInt8(truncatingIfNeeded: value))
        }

        mutating func writeUInt32(_ value: UInt32) {
            bytes.append(UInt8(truncatingIfNeeded: value >> 24))
            bytes.append(UInt8(truncatingIfNeeded: value >> 16))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
            bytes.append(UInt8(truncatingIfNeeded: value))
        }

        mutating func writeUInt64(_ value: UInt64) {
            bytes.append(UInt8(truncatingIfNeeded: value >> 56))
            bytes.append(UInt8(truncatingIfNeeded: value >> 48))
            bytes.append(UInt8(truncatingIfNeeded: value >> 40))
            bytes.append(UInt8(truncatingIfNeeded: value >> 32))
            bytes.append(UInt8(truncatingIfNeeded: value >> 24))
            bytes.append(UInt8(truncatingIfNeeded: value >> 16))
            bytes.append(UInt8(truncatingIfNeeded: value >> 8))
            bytes.append(UInt8(truncatingIfNeeded: value))
        }

        mutating func writeBool(_ value: Bool) {
            writeUInt8(value ? 0x01 : 0x00)
        }

        mutating func writeBytes(_ value: [UInt8]) throws {
            try writeLength(value.count)
            bytes.append(contentsOf: value)
        }

        mutating func writeText(_ value: String) throws {
            let encodedText = Array(value.utf8)
            guard encodedText.allSatisfy({ (0x20 ... 0x7E).contains($0) }) else {
                throw CanonicalCodingError.nonPrintableASCIIText
            }
            try writeBytes(encodedText)
        }

        mutating func writeOptional<Value>(
            _ value: Value?,
            writingValueWith writeValue: (inout Self, Value) throws -> Void
        ) rethrows {
            guard let value else {
                writeBool(false)
                return
            }

            writeBool(true)
            try writeValue(&self, value)
        }

        mutating func writeVector<Value>(
            _ values: [Value],
            writingValueWith writeValue: (inout Self, Value) throws -> Void
        ) throws {
            try writeLength(values.count)
            for value in values {
                try writeValue(&self, value)
            }
        }

        mutating func writeSortedSet<Value>(
            _ values: [Value],
            writingValueWith writeValue: (inout Self, Value) throws -> Void
        ) throws {
            var encodedMembers: [[UInt8]] = []
            encodedMembers.reserveCapacity(values.count)
            for value in values {
                var memberEncoder = Self()
                try writeValue(&memberEncoder, value)
                encodedMembers.append(memberEncoder.encodedBytes)
            }
            encodedMembers.sort(by: { $0.lexicographicallyPrecedes($1) })

            for memberIndex in encodedMembers.indices.dropFirst() {
                guard encodedMembers[memberIndex - 1] != encodedMembers[memberIndex] else {
                    throw CanonicalCodingError.duplicateSetMember
                }
            }

            try writeLength(encodedMembers.count)
            for encodedMember in encodedMembers {
                bytes.append(contentsOf: encodedMember)
            }
        }

        private mutating func writeLength(_ count: Int) throws {
            guard let encodedCount = UInt32(exactly: count) else {
                throw CanonicalCodingError.lengthExceedsUInt32(count)
            }
            writeUInt32(encodedCount)
        }
    }
}
