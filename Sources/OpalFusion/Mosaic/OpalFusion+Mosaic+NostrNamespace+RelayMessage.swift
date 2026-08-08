// OpalFusion+Mosaic+NostrNamespace+RelayMessage.swift

import OpalCrypto

extension OpalFusion.Mosaic.NostrNamespace {
    /// A NIP-01 subscription identifier.
    struct SubscriptionIdentifier: Sendable, Hashable {
        let value: String

        init(_ value: String) throws {
            guard !value.isEmpty,
                  value.count <= 64,
                  value.unicodeScalars.allSatisfy({
                      $0.value >= 0x20 && $0.value != 0x7F
                  }) else {
                throw RelayMessageCodingError.invalidSubscriptionIdentifier
            }
            self.value = value
        }
    }

    /// The exact-key filter subset needed by Mosaic relay subscriptions.
    ///
    /// Prefix matching and arbitrary single-letter tag filters remain outside this bounded adapter.
    struct RelayFilter: Sendable, Equatable {
        let identifiers: [OpalCrypto.Signature.Digest]
        let authors: [OpalCrypto.Signature.BIP340.VerificationKey]
        let kinds: [UInt16]
        let recipientPublicKeys: [OpalCrypto.Signature.BIP340.VerificationKey]
        let since: UInt64?
        let until: UInt64?
        let limit: Int?

        init(
            identifiers: [OpalCrypto.Signature.Digest] = [],
            authors: [OpalCrypto.Signature.BIP340.VerificationKey] = [],
            kinds: [UInt16] = [],
            recipientPublicKeys: [OpalCrypto.Signature.BIP340.VerificationKey] = [],
            since: UInt64? = nil,
            until: UInt64? = nil,
            limit: Int? = nil
        ) throws {
            try Self.requireDistinct(identifiers, field: "ids")
            try Self.requireDistinct(authors, field: "authors")
            try Self.requireDistinct(kinds, field: "kinds")
            try Self.requireDistinct(recipientPublicKeys, field: "#p")
            if let since, let until, since > until {
                throw RelayMessageCodingError.invalidFilterTimeRange
            }
            if let limit, limit < 0 {
                throw RelayMessageCodingError.invalidFilterLimit
            }
            self.identifiers = identifiers
            self.authors = authors
            self.kinds = kinds
            self.recipientPublicKeys = recipientPublicKeys
            self.since = since
            self.until = until
            self.limit = limit
        }

        private static func requireDistinct<Value: Equatable>(
            _ values: [Value],
            field: String
        ) throws {
            for (index, value) in values.enumerated() {
                guard !values[..<index].contains(value) else {
                    throw RelayMessageCodingError.duplicateFilterValue(field: field)
                }
            }
        }
    }

    struct RelaySubscription: Sendable, Equatable {
        let identifier: SubscriptionIdentifier
        let filters: [RelayFilter]

        init(
            identifier: SubscriptionIdentifier,
            filters: [RelayFilter]
        ) throws {
            guard !filters.isEmpty else {
                throw RelayMessageCodingError.emptyFilterSet
            }
            self.identifier = identifier
            self.filters = filters
        }
    }

    enum RelayClientMessage: Sendable, Equatable {
        case event(Event)
        case request(RelaySubscription)
        case close(SubscriptionIdentifier)
    }

    enum RelayServerMessage: Sendable, Equatable {
        case event(subscription: SubscriptionIdentifier, event: Event)
        case acknowledgement(
            eventIdentifier: OpalCrypto.Signature.Digest,
            accepted: Bool,
            message: String
        )
        case endOfStoredEvents(SubscriptionIdentifier)
        case subscriptionClosed(identifier: SubscriptionIdentifier, message: String)
        case notice(String)
    }
}
