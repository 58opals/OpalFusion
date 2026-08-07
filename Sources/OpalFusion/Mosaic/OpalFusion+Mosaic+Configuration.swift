// OpalFusion+Mosaic+Configuration.swift

public extension OpalFusion.Mosaic {
    /// An authoritative Mosaic profile selection.
    ///
    /// This type does not imply that a live Mosaic runtime or transport is available.
    struct Configuration: Sendable, Equatable {
        public let profile: Profile

        public init(profile: Profile = .draft1) {
            self.profile = profile
        }

        public var protocolVersion: ProtocolVersion { profile.protocolVersion }

        public var rosterPolicy: RosterPolicy { profile.rosterPolicy }

        public var transportProfile: TransportProfile { profile.transportProfile }
    }
}
