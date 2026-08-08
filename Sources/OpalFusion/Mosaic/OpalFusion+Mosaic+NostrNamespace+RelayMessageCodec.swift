// OpalFusion+Mosaic+NostrNamespace+RelayMessageCodec.swift

import Foundation
import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    /// Strict NIP-01 client-frame encoding and server-frame decoding.
    enum RelayMessageCodec {
        static func encode(
            _ message: RelayClientMessage,
            limits: RelayMessageCodingLimits
        ) throws -> Data {
            let json: String
            switch message {
            case let .event(event):
                let encodedEvent = try EventCodec.encode(event, limits: limits.event)
                json = "[\"EVENT\"," + String(decoding: encodedEvent, as: UTF8.self) + "]"

            case let .request(subscription):
                try validateString(
                    subscription.identifier.value,
                    limits: limits
                )
                guard subscription.filters.count <= limits.maximumFiltersPerRequest else {
                    throw RelayMessageCodingError.filterCountExceedsMaximum(
                        maximum: limits.maximumFiltersPerRequest,
                        actual: subscription.filters.count
                    )
                }
                let filters = try subscription.filters.map {
                    try encode($0, limits: limits)
                }.joined(separator: ",")
                json = "[\"REQ\","
                    + EventCodec.encodeString(subscription.identifier.value)
                    + "," + filters + "]"

            case let .close(identifier):
                try validateString(identifier.value, limits: limits)
                json = "[\"CLOSE\","
                    + EventCodec.encodeString(identifier.value) + "]"
            }

            let data = Data(json.utf8)
            try validateFrameByteCount(data.count, limits: limits)
            return data
        }

        static func decodeServerMessage(
            _ data: Data,
            limits: RelayMessageCodingLimits
        ) throws -> RelayServerMessage {
            try validateFrameByteCount(data.count, limits: limits)
            let elements = try JSONArrayScanner.elements(in: data)
            guard let typeData = elements.first else {
                throw RelayMessageCodingError.invalidMessageShape
            }
            let type: String = try decodeJSON(String.self, from: typeData)

            switch type {
            case "EVENT":
                guard elements.count == 3 else {
                    throw RelayMessageCodingError.invalidMessageShape
                }
                let subscription = try decodeSubscriptionIdentifier(
                    elements[1],
                    limits: limits
                )
                let event = try EventCodec.decode(elements[2], limits: limits.event)
                return .event(subscription: subscription, event: event)

            case "OK":
                guard elements.count == 4 else {
                    throw RelayMessageCodingError.invalidMessageShape
                }
                let identifier = try decodeEventIdentifier(elements[1])
                let accepted: Bool = try decodeJSON(Bool.self, from: elements[2])
                let message = try decodeMessageString(elements[3], limits: limits)
                return .acknowledgement(
                    eventIdentifier: identifier,
                    accepted: accepted,
                    message: message
                )

            case "EOSE":
                guard elements.count == 2 else {
                    throw RelayMessageCodingError.invalidMessageShape
                }
                return .endOfStoredEvents(
                    try decodeSubscriptionIdentifier(elements[1], limits: limits)
                )

            case "CLOSED":
                guard elements.count == 3 else {
                    throw RelayMessageCodingError.invalidMessageShape
                }
                return .subscriptionClosed(
                    identifier: try decodeSubscriptionIdentifier(
                        elements[1],
                        limits: limits
                    ),
                    message: try decodeMessageString(elements[2], limits: limits)
                )

            case "NOTICE":
                guard elements.count == 2 else {
                    throw RelayMessageCodingError.invalidMessageShape
                }
                return .notice(
                    try decodeMessageString(elements[1], limits: limits)
                )

            default:
                throw RelayMessageCodingError.unsupportedMessageType(type)
            }
        }

        private static func encode(
            _ filter: RelayFilter,
            limits: RelayMessageCodingLimits
        ) throws -> String {
            let valueCounts = [
                filter.identifiers.count,
                filter.authors.count,
                filter.kinds.count,
                filter.recipientPublicKeys.count,
            ]
            guard let actual = valueCounts.first(where: {
                $0 > limits.maximumValuesPerFilter
            }) else {
                var fields: [String] = []
                if !filter.identifiers.isEmpty {
                    fields.append(
                        "\"ids\":" + encodeHexadecimalValues(
                            filter.identifiers.map(\.rawRepresentation)
                        )
                    )
                }
                if !filter.authors.isEmpty {
                    fields.append(
                        "\"authors\":" + encodeHexadecimalValues(
                            filter.authors.map(\.rawRepresentation)
                        )
                    )
                }
                if !filter.kinds.isEmpty {
                    fields.append(
                        "\"kinds\":["
                            + filter.kinds.map(String.init).joined(separator: ",")
                            + "]"
                    )
                }
                if !filter.recipientPublicKeys.isEmpty {
                    fields.append(
                        "\"#p\":" + encodeHexadecimalValues(
                            filter.recipientPublicKeys.map(\.rawRepresentation)
                        )
                    )
                }
                if let since = filter.since {
                    fields.append("\"since\":" + String(since))
                }
                if let until = filter.until {
                    fields.append("\"until\":" + String(until))
                }
                if let limit = filter.limit {
                    fields.append("\"limit\":" + String(limit))
                }
                return "{" + fields.joined(separator: ",") + "}"
            }
            throw RelayMessageCodingError.filterValueCountExceedsMaximum(
                maximum: limits.maximumValuesPerFilter,
                actual: actual
            )
        }

        private static func encodeHexadecimalValues(
            _ values: [Data]
        ) -> String {
            "[" + values.map {
                EventCodec.encodeString(EventCodec.hexadecimal($0))
            }.joined(separator: ",") + "]"
        }

        private static func decodeSubscriptionIdentifier(
            _ data: Data,
            limits: RelayMessageCodingLimits
        ) throws -> SubscriptionIdentifier {
            let value: String = try decodeJSON(String.self, from: data)
            try validateString(value, limits: limits)
            return try SubscriptionIdentifier(value)
        }

        private static func decodeEventIdentifier(
            _ data: Data
        ) throws -> OpalCrypto.Signature.Digest {
            let value: String = try decodeJSON(String.self, from: data)
            let rawRepresentation: Data
            do {
                rawRepresentation = try EventCodec.decodeHexadecimal(
                    value,
                    field: "eventIdentifier"
                )
            } catch {
                throw RelayMessageCodingError.invalidEventIdentifier
            }
            guard rawRepresentation.count == 32,
                  let identifier = try? OpalCrypto.Signature.Digest(
                      rawRepresentation: rawRepresentation
                  ) else {
                throw RelayMessageCodingError.invalidEventIdentifier
            }
            return identifier
        }

        private static func decodeMessageString(
            _ data: Data,
            limits: RelayMessageCodingLimits
        ) throws -> String {
            let value: String = try decodeJSON(String.self, from: data)
            try validateString(value, limits: limits)
            return value
        }

        private static func decodeJSON<Value: Decodable>(
            _ type: Value.Type,
            from data: Data
        ) throws -> Value {
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                throw RelayMessageCodingError.invalidJSON
            }
        }

        private static func validateString(
            _ value: String,
            limits: RelayMessageCodingLimits
        ) throws {
            let byteCount = value.utf8.count
            guard byteCount <= limits.maximumMessageStringByteCount else {
                throw RelayMessageCodingError.messageStringByteCountExceedsMaximum(
                    maximum: limits.maximumMessageStringByteCount,
                    actual: byteCount
                )
            }
        }

        private static func validateFrameByteCount(
            _ byteCount: Int,
            limits: RelayMessageCodingLimits
        ) throws {
            guard byteCount <= limits.maximumFrameByteCount else {
                throw RelayMessageCodingError.frameByteCountExceedsMaximum(
                    maximum: limits.maximumFrameByteCount,
                    actual: byteCount
                )
            }
        }
    }
}
