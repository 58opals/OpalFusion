// OpalFusion+Mosaic+Nostr+EventCodec~Encoding.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.Nostr.EventCodec {
    static func identifierPreimage(
        publicKey: OpalCrypto.Signature.BIP340.VerificationKey,
        template: OpalFusion.Mosaic.Nostr.EventTemplate,
        limits: OpalFusion.Mosaic.Nostr.EventCodingLimits
    ) throws -> Data {
        try validate(
            tags: template.tags,
            content: template.content,
            limits: limits
        )
        let json = "[0,\""
            + hexadecimal(publicKey.rawRepresentation)
            + "\"," + String(template.createdAt)
            + "," + String(template.kind)
            + "," + encodeTags(template.tags)
            + "," + encodeString(template.content) + "]"
        let data = Data(json.utf8)
        try validateJSONByteCount(data.count, limits: limits)
        return data
    }

    static func encodeTags(_ tags: [[String]]) -> String {
        "[" + tags.map { tag in
            "[" + tag.map(encodeString).joined(separator: ",") + "]"
        }.joined(separator: ",") + "]"
    }

    static func encodeString(_ value: String) -> String {
        var result = "\""
        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x08: result += "\\b"
            case 0x09: result += "\\t"
            case 0x0A: result += "\\n"
            case 0x0C: result += "\\f"
            case 0x0D: result += "\\r"
            case 0x22: result += "\\\""
            case 0x5C: result += "\\\\"
            case 0x00 ... 0x1F:
                result += String(
                    format: "\\u%04x",
                    scalar.value
                )
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        result += "\""
        return result
    }

    static func hexadecimal(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }
}
