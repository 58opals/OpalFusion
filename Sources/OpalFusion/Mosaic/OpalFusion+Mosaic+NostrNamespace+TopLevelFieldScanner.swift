// OpalFusion+Mosaic+NostrNamespace+TopLevelFieldScanner.swift

import Foundation

extension OpalFusion.Mosaic.NostrNamespace {
    enum TopLevelFieldScanner {
        static func fields(in data: Data) throws -> [String] {
            let bytes = [UInt8](data)
            var cursor = skipWhitespace(in: bytes, from: 0)
            guard cursor < bytes.count, bytes[cursor] == 0x7B else {
                throw EventCodingError.invalidJSON
            }
            cursor += 1
            var fields: [String] = []

            while true {
                cursor = skipWhitespace(in: bytes, from: cursor)
                guard cursor < bytes.count else {
                    throw EventCodingError.invalidJSON
                }
                if bytes[cursor] == 0x7D {
                    return fields
                }
                let field = try readField(in: bytes, cursor: &cursor)
                fields.append(field)
                try skipValue(in: bytes, cursor: &cursor)
                cursor = skipWhitespace(in: bytes, from: cursor)
                guard cursor < bytes.count else {
                    throw EventCodingError.invalidJSON
                }
                if bytes[cursor] == 0x2C {
                    cursor += 1
                    continue
                }
                guard bytes[cursor] == 0x7D else {
                    throw EventCodingError.invalidJSON
                }
                return fields
            }
        }

        private static func readField(
            in bytes: [UInt8],
            cursor: inout Int
        ) throws -> String {
            guard cursor < bytes.count, bytes[cursor] == 0x22 else {
                throw EventCodingError.invalidJSON
            }
            cursor += 1
            let start = cursor
            while cursor < bytes.count, bytes[cursor] != 0x22 {
                guard bytes[cursor] != 0x5C,
                      bytes[cursor] >= 0x20,
                      bytes[cursor] < 0x80 else {
                    throw EventCodingError.invalidJSON
                }
                cursor += 1
            }
            guard cursor < bytes.count,
                  let field = String(
                      bytes: bytes[start ..< cursor],
                      encoding: .utf8
                  ) else {
                throw EventCodingError.invalidJSON
            }
            cursor += 1
            cursor = skipWhitespace(in: bytes, from: cursor)
            guard cursor < bytes.count, bytes[cursor] == 0x3A else {
                throw EventCodingError.invalidJSON
            }
            cursor += 1
            return field
        }

        private static func skipValue(
            in bytes: [UInt8],
            cursor: inout Int
        ) throws {
            cursor = skipWhitespace(in: bytes, from: cursor)
            var objectDepth = 0
            var arrayDepth = 0
            var inString = false
            var isEscaped = false
            while cursor < bytes.count {
                let byte = bytes[cursor]
                if inString {
                    if isEscaped {
                        isEscaped = false
                    } else if byte == 0x5C {
                        isEscaped = true
                    } else if byte == 0x22 {
                        inString = false
                    } else if byte < 0x20 {
                        throw EventCodingError.invalidJSON
                    }
                } else {
                    switch byte {
                    case 0x22: inString = true
                    case 0x7B: objectDepth += 1
                    case 0x7D:
                        if objectDepth == 0, arrayDepth == 0 { return }
                        objectDepth -= 1
                    case 0x5B: arrayDepth += 1
                    case 0x5D: arrayDepth -= 1
                    case 0x2C where objectDepth == 0 && arrayDepth == 0:
                        return
                    default: break
                    }
                    guard objectDepth >= 0, arrayDepth >= 0 else {
                        throw EventCodingError.invalidJSON
                    }
                }
                cursor += 1
            }
            throw EventCodingError.invalidJSON
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
    }
}
