// OpalFusion+Mosaic+OpalV0+PaddedEnvelopeCodec.swift

extension OpalFusion.Mosaic.OpalV0 {
    struct PaddedEnvelopeCodec: Sendable {
        enum CodingError: Error, Sendable, Equatable {
            case payloadTooLarge(maximum: Int, actual: Int)
            case invalidEncodedLength(expected: Int, actual: Int)
            case invalidLowercaseHexadecimal
            case declaredPayloadTooLarge(maximum: Int, actual: Int)
            case nonzeroPadding
        }

        static func encode(_ payload: [UInt8]) throws -> String {
            guard payload.count <= OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount else {
                throw CodingError.payloadTooLarge(
                    maximum: OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount,
                    actual: payload.count
                )
            }

            var bytes = lowercaseHexadecimal(UInt32(payload.count), width: 8)
            bytes.reserveCapacity(OpalFusion.Mosaic.OpalV0.paddedInnerPlaintextByteCount)
            for byte in payload {
                bytes.append(hexDigit(byte >> 4))
                bytes.append(hexDigit(byte & 0x0f))
            }
            bytes.append(
                contentsOf: repeatElement(
                    UInt8(ascii: "0"),
                    count: OpalFusion.Mosaic.OpalV0.paddedInnerPlaintextByteCount
                        - bytes.count
                )
            )
            return String(decoding: bytes, as: UTF8.self)
        }

        static func decode(_ encoded: String) throws -> [UInt8] {
            let bytes = Array(encoded.utf8)
            guard bytes.count == OpalFusion.Mosaic.OpalV0.paddedInnerPlaintextByteCount else {
                throw CodingError.invalidEncodedLength(
                    expected: OpalFusion.Mosaic.OpalV0.paddedInnerPlaintextByteCount,
                    actual: bytes.count
                )
            }
            guard bytes.allSatisfy({ hexadecimalValue($0) != nil }) else {
                throw CodingError.invalidLowercaseHexadecimal
            }

            var declaredLength: UInt32 = 0
            for byte in bytes.prefix(8) {
                declaredLength = (declaredLength << 4) | UInt32(hexadecimalValue(byte)!)
            }
            let payloadLength = Int(declaredLength)
            guard payloadLength <= OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount else {
                throw CodingError.declaredPayloadTooLarge(
                    maximum: OpalFusion.Mosaic.OpalV0.maximumInnerPayloadByteCount,
                    actual: payloadLength
                )
            }

            let payloadEnd = 8 + payloadLength * 2
            guard payloadEnd == bytes.count
                || bytes[payloadEnd ..< bytes.count].allSatisfy({
                    $0 == UInt8(ascii: "0")
                }) else {
                throw CodingError.nonzeroPadding
            }

            var payload: [UInt8] = []
            payload.reserveCapacity(payloadLength)
            var index = 8
            while index < payloadEnd {
                let high = hexadecimalValue(bytes[index])!
                let low = hexadecimalValue(bytes[index + 1])!
                payload.append((high << 4) | low)
                index += 2
            }
            return payload
        }

        private static func lowercaseHexadecimal(_ value: UInt32, width: Int) -> [UInt8] {
            (0 ..< width).map { index in
                let shift = UInt32((width - index - 1) * 4)
                return hexDigit(UInt8(truncatingIfNeeded: value >> shift) & 0x0f)
            }
        }

        private static func hexDigit(_ value: UInt8) -> UInt8 {
            value < 10 ? UInt8(ascii: "0") + value : UInt8(ascii: "a") + value - 10
        }

        private static func hexadecimalValue(_ byte: UInt8) -> UInt8? {
            switch byte {
            case UInt8(ascii: "0") ... UInt8(ascii: "9"):
                byte - UInt8(ascii: "0")
            case UInt8(ascii: "a") ... UInt8(ascii: "f"):
                byte - UInt8(ascii: "a") + 10
            default:
                nil
            }
        }
    }
}
