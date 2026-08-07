// OpalFusion+Mosaic+TransportProfile.swift

public extension OpalFusion.Mosaic {
    /// A transport contract identified by the Mosaic protocol specification.
    enum TransportProfile: String, CaseIterable, Sendable {
        /// Nostr-compatible relay mailboxes reached exclusively through Tor.
        case nostrTorDraft1 = "nostr-tor/1-draft.1"

        /// Deterministic Nostr event contracts without a live network adapter.
        case nostrConformanceOpalV0 = "nostr-conformance/0-opal.1"
    }
}
