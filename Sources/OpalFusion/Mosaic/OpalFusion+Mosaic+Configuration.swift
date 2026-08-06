// OpalFusion+Mosaic+Configuration.swift

public extension OpalFusion.Mosaic {
    /// A draft Mosaic profile selection.
    ///
    /// This type does not imply that a live Mosaic runtime or transport is available.
    struct Configuration: Sendable, Equatable {
        public let protocolVersion: ProtocolVersion
        public let rosterPolicy: RosterPolicy
        public let transportProfile: TransportProfile

        public init(
            protocolVersion: ProtocolVersion = .draft1,
            rosterPolicy: RosterPolicy = .draft1,
            transportProfile: TransportProfile = .nostrTorDraft1
        ) {
            self.protocolVersion = protocolVersion
            self.rosterPolicy = rosterPolicy
            self.transportProfile = transportProfile
        }
    }
}
