// OpalFusion+Mosaic+Profile.swift

public extension OpalFusion.Mosaic {
    /// A cohesive set of Mosaic protocol, roster, transport, and host constants.
    enum Profile: String, CaseIterable, Sendable {
        /// The repository's non-interoperability draft.
        case draft1 = "Mosaic/1-draft.1"

        /// The Opal-owned, chipnet-only v0 conformance profile.
        ///
        /// This profile is not a live, privacy-audited, or mainnet-capable engine.
        case opalV0 = "Mosaic/0-opal.1"

        /// The additive, explicitly selected mainnet-alpha protocol contract.
        ///
        /// Selecting this profile does not provide relay endpoints, a Tor route, wallet policy,
        /// broadcast permission, or a runnable public session.
        case opalMainnetAlpha = "Mosaic/0-opal-mainnet-alpha.2"

        public var protocolVersion: ProtocolVersion {
            switch self {
            case .draft1: .draft1
            case .opalV0: .opalV0
            case .opalMainnetAlpha: .opalMainnetAlpha
            }
        }

        public var rosterPolicy: RosterPolicy {
            switch self {
            case .draft1: .draft1
            case .opalV0: .opalV0
            case .opalMainnetAlpha: .opalMainnetAlpha
            }
        }

        public var transportProfile: TransportProfile {
            switch self {
            case .draft1: .nostrTorDraft1
            case .opalV0: .nostrConformanceOpalV0
            case .opalMainnetAlpha: .nostrTorOpalMainnetAlpha
            }
        }

        /// The transaction rules a wallet host must apply for this profile.
        public var transactionProfileIdentifier: String {
            switch self {
            case .draft1: "mosaic-bch-p2pkh-draft"
            case .opalV0: "bch-chipnet-p2pkh-schnorr/0-opal.1"
            case .opalMainnetAlpha:
                "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.2"
            }
        }

        /// The conventional display-order genesis hash when the profile fixes a network.
        public var networkGenesisHash: [UInt8]? {
            switch self {
            case .draft1:
                nil
            case .opalV0:
                OpalFusion.Mosaic.OpalV0.chipnetGenesisHash
            case .opalMainnetAlpha:
                OpalFusion.Mosaic.OpalMainnetAlpha.mainnetGenesisHash
            }
        }

        var supportsExecutableCore: Bool {
            switch self {
            case .opalV0, .opalMainnetAlpha:
                true
            case .draft1:
                false
            }
        }

        var supportsRuntimeSessionDriver: Bool {
            switch self {
            case .opalV0:
                true
            case .draft1, .opalMainnetAlpha:
                false
            }
        }
    }
}
