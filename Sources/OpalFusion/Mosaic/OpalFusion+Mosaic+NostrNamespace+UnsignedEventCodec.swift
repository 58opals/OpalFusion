// OpalFusion+Mosaic+NostrNamespace+UnsignedEventCodec.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    /// Strict JSON coding for the unsigned NIP-01 event carried by NIP-59.
    enum UnsignedEventCodec {
        private static let expectedTopLevelFields: Set<String> = [
            "id", "pubkey", "created_at", "kind", "tags", "content"
        ]

        static func encode(
            _ event: UnsignedEvent,
            limits: EventCodingLimits
        ) throws -> Data {
            try EventCodec.validate(
                tags: event.template.tags,
                content: event.template.content,
                limits: limits
            )
            let json = "{\"id\":\""
                + EventCodec.hexadecimal(event.identifier.rawRepresentation)
                + "\",\"pubkey\":\""
                + EventCodec.hexadecimal(event.publicKey.rawRepresentation)
                + "\",\"created_at\":"
                + String(event.template.createdAt)
                + ",\"kind\":" + String(event.template.kind)
                + ",\"tags\":" + EventCodec.encodeTags(event.template.tags)
                + ",\"content\":" + EventCodec.encodeString(event.template.content)
                + "}"
            let data = Data(json.utf8)
            try EventCodec.validateJSONByteCount(data.count, limits: limits)
            return data
        }

        static func decode(
            _ data: Data,
            limits: EventCodingLimits
        ) throws -> UnsignedEvent {
            try EventCodec.validateJSONByteCount(data.count, limits: limits)
            try validateTopLevelFields(in: data)

            let wire: WireEvent
            do {
                wire = try JSONDecoder().decode(WireEvent.self, from: data)
            } catch {
                throw EventCodingError.invalidJSON
            }

            let identifierBytes = try EventCodec.decodeHexadecimal(
                wire.id,
                field: "id"
            )
            guard identifierBytes.count == 32 else {
                throw EventCodingError.invalidIdentifierLength(
                    actual: identifierBytes.count
                )
            }

            let publicKey: OpalCrypto.Signature.BIP340.VerificationKey
            do {
                publicKey = try .init(
                    rawRepresentation: EventCodec.decodeHexadecimal(
                        wire.pubkey,
                        field: "pubkey"
                    )
                )
            } catch let error as EventCodingError {
                throw error
            } catch {
                throw EventCodingError.invalidPublicKey
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
            return try UnsignedEvent(
                identifier: identifier,
                publicKey: publicKey,
                template: template,
                limits: limits
            )
        }

        private static func validateTopLevelFields(in data: Data) throws {
            let fields = try TopLevelFieldScanner.fields(in: data)
            var found = Set<String>()
            for field in fields {
                guard expectedTopLevelFields.contains(field) else {
                    throw EventCodingError.unexpectedTopLevelField(field)
                }
                guard found.insert(field).inserted else {
                    throw EventCodingError.duplicateTopLevelField(field)
                }
            }
            for field in expectedTopLevelFields where !found.contains(field) {
                throw EventCodingError.missingTopLevelField(field)
            }
        }
    }
}

extension OpalFusion.Mosaic.NostrNamespace.UnsignedEventCodec {
    struct WireEvent: Decodable {
        let id: String
        let pubkey: String
        let createdAt: UInt64
        let kind: UInt16
        let tags: [[String]]
        let content: String

        enum CodingKeys: String, CodingKey {
            case id, pubkey, kind, tags, content
            case createdAt = "created_at"
        }
    }
}
