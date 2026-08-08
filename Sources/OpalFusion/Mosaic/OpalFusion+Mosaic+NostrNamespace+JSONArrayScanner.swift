// OpalFusion+Mosaic+NostrNamespace+JSONArrayScanner.swift

import Foundation

extension OpalFusion.Mosaic.NostrNamespace {
    /// Preserves each top-level element's exact bytes so embedded events retain strict field checks.
    enum JSONArrayScanner {
        static func elements(in data: Data) throws -> [Data] {
            let bytes = [UInt8](data)
            var cursor = skipWhitespace(in: bytes, from: 0)
            guard cursor < bytes.count, bytes[cursor] == 0x5B else {
                throw RelayMessageCodingError.invalidJSON
            }
            cursor += 1
            cursor = skipWhitespace(in: bytes, from: cursor)
            if cursor < bytes.count, bytes[cursor] == 0x5D {
                cursor += 1
                try requireEnd(in: bytes, cursor: cursor)
                return []
            }

            var result: [Data] = []
            while true {
                cursor = skipWhitespace(in: bytes, from: cursor)
                let start = cursor
                try skipValue(in: bytes, cursor: &cursor)
                guard cursor > start else {
                    throw RelayMessageCodingError.invalidJSON
                }
                result.append(Data(bytes[start ..< cursor]))
                cursor = skipWhitespace(in: bytes, from: cursor)
                guard cursor < bytes.count else {
                    throw RelayMessageCodingError.invalidJSON
                }
                switch bytes[cursor] {
                case 0x2C:
                    cursor += 1
                    let next = skipWhitespace(in: bytes, from: cursor)
                    guard next < bytes.count, bytes[next] != 0x5D else {
                        throw RelayMessageCodingError.invalidJSON
                    }
                    cursor = next
                case 0x5D:
                    cursor += 1
                    try requireEnd(in: bytes, cursor: cursor)
                    return result
                default:
                    throw RelayMessageCodingError.invalidJSON
                }
            }
        }

        private static func skipValue(
            in bytes: [UInt8],
            cursor: inout Int
        ) throws {
            guard cursor < bytes.count else {
                throw RelayMessageCodingError.invalidJSON
            }
            switch bytes[cursor] {
            case 0x22:
                try skipString(in: bytes, cursor: &cursor)
            case 0x5B, 0x7B:
                try skipComposite(in: bytes, cursor: &cursor)
            default:
                let start = cursor
                while cursor < bytes.count,
                      ![0x2C, 0x5D, 0x20, 0x09, 0x0A, 0x0D]
                          .contains(bytes[cursor]) {
                    cursor += 1
                }
                guard cursor > start else {
                    throw RelayMessageCodingError.invalidJSON
                }
            }
        }

        private static func skipComposite(
            in bytes: [UInt8],
            cursor: inout Int
        ) throws {
            var stack: [UInt8] = []
            while cursor < bytes.count {
                switch bytes[cursor] {
                case 0x22:
                    try skipString(in: bytes, cursor: &cursor)
                    continue
                case 0x5B:
                    stack.append(0x5D)
                case 0x7B:
                    stack.append(0x7D)
                case 0x5D, 0x7D:
                    guard stack.last == bytes[cursor] else {
                        throw RelayMessageCodingError.invalidJSON
                    }
                    stack.removeLast()
                    cursor += 1
                    if stack.isEmpty { return }
                    continue
                default:
                    break
                }
                cursor += 1
            }
            throw RelayMessageCodingError.invalidJSON
        }

        private static func skipString(
            in bytes: [UInt8],
            cursor: inout Int
        ) throws {
            guard bytes[cursor] == 0x22 else {
                throw RelayMessageCodingError.invalidJSON
            }
            cursor += 1
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if byte == 0x22 {
                    cursor += 1
                    return
                }
                if byte == 0x5C {
                    cursor += 1
                    guard cursor < bytes.count else {
                        throw RelayMessageCodingError.invalidJSON
                    }
                    if bytes[cursor] == 0x75 {
                        guard cursor + 4 < bytes.count,
                              bytes[(cursor + 1) ... (cursor + 4)]
                                  .allSatisfy(Self.isHexadecimal) else {
                            throw RelayMessageCodingError.invalidJSON
                        }
                        cursor += 5
                        continue
                    }
                    guard [0x22, 0x5C, 0x2F, 0x62, 0x66, 0x6E, 0x72, 0x74]
                        .contains(bytes[cursor]) else {
                        throw RelayMessageCodingError.invalidJSON
                    }
                } else {
                    guard byte >= 0x20 else {
                        throw RelayMessageCodingError.invalidJSON
                    }
                }
                cursor += 1
            }
            throw RelayMessageCodingError.invalidJSON
        }

        private static func requireEnd(
            in bytes: [UInt8],
            cursor: Int
        ) throws {
            guard skipWhitespace(in: bytes, from: cursor) == bytes.count else {
                throw RelayMessageCodingError.invalidJSON
            }
        }

        private static func skipWhitespace(
            in bytes: [UInt8],
            from start: Int
        ) -> Int {
            var cursor = start
            while cursor < bytes.count,
                  [0x20, 0x09, 0x0A, 0x0D].contains(bytes[cursor]) {
                cursor += 1
            }
            return cursor
        }

        private static func isHexadecimal(_ byte: UInt8) -> Bool {
            (0x30 ... 0x39).contains(byte)
                || (0x41 ... 0x46).contains(byte)
                || (0x61 ... 0x66).contains(byte)
        }
    }
}
