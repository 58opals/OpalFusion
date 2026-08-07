// OpalFusion+Mosaic+NostrNamespace+EventCodec.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    enum EventCodec {
        static func identifier(
            publicKey: OpalCrypto.Signature.BIP340.VerificationKey,
            template: EventTemplate,
            limits: EventCodingLimits
        ) throws -> OpalCrypto.Signature.Digest {
            let preimage = try identifierPreimage(
                publicKey: publicKey,
                template: template,
                limits: limits
            )
            return try OpalCrypto.Signature.Digest(
                rawRepresentation: OpalCrypto.Hashing.sha256(preimage)
            )
        }

        static func encode(
            _ event: Event,
            limits: EventCodingLimits
        ) throws -> Data {
            try validate(
                tags: event.template.tags,
                content: event.template.content,
                limits: limits
            )
            let json = "{\"id\":\""
                + hexadecimal(event.identifier.rawRepresentation)
                + "\",\"pubkey\":\""
                + hexadecimal(event.publicKey.rawRepresentation)
                + "\",\"created_at\":"
                + String(event.template.createdAt)
                + ",\"kind\":" + String(event.template.kind)
                + ",\"tags\":" + encodeTags(event.template.tags)
                + ",\"content\":" + encodeString(event.template.content)
                + ",\"sig\":\""
                + hexadecimal(event.signature.rawRepresentation) + "\"}"
            let data = Data(json.utf8)
            try validateJSONByteCount(data.count, limits: limits)
            return data
        }

        static func decode(
            _ data: Data,
            limits: EventCodingLimits
        ) throws -> Event {
            try validateJSONByteCount(data.count, limits: limits)
            try validateTopLevelFields(in: data)
            let wire: WireEvent
            do {
                wire = try JSONDecoder().decode(WireEvent.self, from: data)
            } catch {
                throw EventCodingError.invalidJSON
            }
            let identifierBytes = try decodeHexadecimal(
                wire.id,
                field: "id"
            )
            guard identifierBytes.count == 32 else {
                throw EventCodingError.invalidIdentifierLength(
                    actual: identifierBytes.count
                )
            }
            let publicKey: OpalCrypto.Signature.BIP340.VerificationKey
            let signature: OpalCrypto.Signature.BIP340
            do {
                publicKey = try .init(
                    rawRepresentation: decodeHexadecimal(
                        wire.pubkey,
                        field: "pubkey"
                    )
                )
            } catch let error as EventCodingError {
                throw error
            } catch {
                throw EventCodingError.invalidPublicKey
            }
            do {
                signature = try .init(
                    rawRepresentation: decodeHexadecimal(
                        wire.sig,
                        field: "sig"
                    )
                )
            } catch let error as EventCodingError {
                throw error
            } catch {
                throw EventCodingError.invalidSignature
            }
            let template = try EventTemplate(
                createdAt: wire.createdAt,
                kind: wire.kind,
                tags: wire.tags,
                content: wire.content,
                limits: limits
            )
            let identifier = try OpalCrypto.Signature.Digest(
                rawRepresentation: identifierBytes
            )
            return try Event(
                identifier: identifier,
                publicKey: publicKey,
                template: template,
                signature: signature,
                limits: limits
            )
        }
    }
}
