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

        public var protocolVersion: ProtocolVersion {
            switch self {
            case .draft1: .draft1
            case .opalV0: .opalV0
            }
        }

        public var rosterPolicy: RosterPolicy {
            switch self {
            case .draft1: .draft1
            case .opalV0: .opalV0
            }
        }

        public var transportProfile: TransportProfile {
            switch self {
            case .draft1: .nostrTorDraft1
            case .opalV0: .nostrConformanceOpalV0
            }
        }

        /// The transaction rules a wallet host must apply for this profile.
        public var transactionProfileIdentifier: String {
            switch self {
            case .draft1: "mosaic-bch-p2pkh-draft"
            case .opalV0: "bch-chipnet-p2pkh-schnorr/0-opal.1"
            }
        }

        /// The conventional display-order chipnet genesis hash when the profile fixes a network.
        public var networkGenesisHash: [UInt8]? {
            switch self {
            case .draft1:
                nil
            case .opalV0:
                OpalFusion.Mosaic.OpalV0.chipnetGenesisHash
            }
        }
    }
}
