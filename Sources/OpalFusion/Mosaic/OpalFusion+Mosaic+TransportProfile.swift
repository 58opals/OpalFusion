// OpalFusion+Mosaic+TransportProfile.swift

public extension OpalFusion.Mosaic {
    /// A transport contract identified by the Mosaic protocol specification.
    enum TransportProfile: String, CaseIterable, Sendable {
        /// Nostr-compatible relay mailboxes reached exclusively through Tor.
        case nostrTorDraft1 = "nostr-tor/1-draft.1"

        /// Deterministic Nostr event contracts without a live network adapter.
        case nostrConformanceOpalV0 = "nostr-conformance/0-opal.1"

        /// Reserved partial Tor/Nostr identifier for the additive mainnet alpha.
        ///
        /// Application-kind mapping, padding, timing, relay policy, and concrete Tor
        /// provisioning remain deployment gates; this does not select a live adapter.
        case nostrTorOpalMainnetAlpha = "nostr-tor/0-opal-mainnet-alpha.4"
    }
}
