// OpalFusion+Mosaic+TransportProfile.swift

public extension OpalFusion.Mosaic {
    /// A transport contract identified by the Mosaic protocol specification.
    enum TransportProfile: String, CaseIterable, Sendable {
        /// Nostr-compatible relay mailboxes reached exclusively through Tor.
        case nostrTorDraft1 = "nostr-tor/1-draft.1"
    }
}
