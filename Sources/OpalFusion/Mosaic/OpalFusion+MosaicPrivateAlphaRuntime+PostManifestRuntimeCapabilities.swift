// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestRuntimeCapabilities.swift

#if os(macOS)
extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// App-owned persistence, mailbox, clock, and Tor capabilities for one exact runtime.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestRuntimeCapabilities: Sendable {
        static let maximumAllowedPendingInputCount = 4_096

        let mailboxes: PostManifestMailboxCapabilities
        let relays: PostManifestRelayCapabilities
        let timing: PostManifestTimingCapabilities
        let admissionPersistence: PostManifestAdmissionPersistence
        let publicationPersistence: PostManifestPublicationPersistence
        let terminalPersistence: PostManifestTerminalPersistence
        let maximumPendingInputCount: Int

        @_spi(MosaicPrivateAlpha)
        public init(
            mailboxes: PostManifestMailboxCapabilities,
            relays: PostManifestRelayCapabilities,
            timing: PostManifestTimingCapabilities,
            admissionPersistence: PostManifestAdmissionPersistence,
            publicationPersistence: PostManifestPublicationPersistence,
            terminalPersistence: PostManifestTerminalPersistence,
            maximumPendingInputCount: Int = 256
        ) {
            self.mailboxes = mailboxes
            self.relays = relays
            self.timing = timing
            self.admissionPersistence = admissionPersistence
            self.publicationPersistence = publicationPersistence
            self.terminalPersistence = terminalPersistence
            self.maximumPendingInputCount = maximumPendingInputCount
        }

        func validateResourceLimits() throws {
            guard (1 ... Self.maximumAllowedPendingInputCount)
                    .contains(maximumPendingInputCount) else {
                throw Failure.invalidStateTransition
            }
            try relays.validateResourceLimits()
        }
    }
}
#endif
