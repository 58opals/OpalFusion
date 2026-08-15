// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestTermination.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Linear package-derived outcome from the exact role coordinator and outbound journal.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestTermination: ~Copyable, Sendable {
        @_spi(MosaicPrivateAlpha) public let binding: Binding
        @_spi(MosaicPrivateAlpha) public let kind:
            PostManifestExecutionOutcomeKind
        @_spi(MosaicPrivateAlpha) public let reservationReference:
            OpalFusion.Host.MosaicReservationReference?
        let terminalIdentity: Data
        let localControlIdentity: Data
        let admissionSnapshotDigest: Data
        let publicationSnapshotDigest: Data
        let authority: PostManifestTerminalAuthority
        let outboundIsDrained: Bool
        let isLocalConductor: Bool
        let receivedTerminalEvent: PrivateDeploymentEvent?
        let localTerminalEvent: PrivateDeploymentEvent?

        init(
            binding: Binding,
            kind: PostManifestExecutionOutcomeKind,
            reservationReference:
                OpalFusion.Host.MosaicReservationReference?,
            terminalIdentity: Data,
            localControlIdentity: Data,
            admissionSnapshotDigest: Data,
            publicationSnapshotDigest: Data,
            authority: PostManifestTerminalAuthority,
            outboundIsDrained: Bool,
            isLocalConductor: Bool,
            receivedTerminalEvent: PrivateDeploymentEvent?,
            localTerminalEvent: PrivateDeploymentEvent?
        ) {
            self.binding = binding
            self.kind = kind
            self.reservationReference = reservationReference
            self.terminalIdentity = terminalIdentity
            self.localControlIdentity = localControlIdentity
            self.admissionSnapshotDigest = admissionSnapshotDigest
            self.publicationSnapshotDigest = publicationSnapshotDigest
            self.authority = authority
            self.outboundIsDrained = outboundIsDrained
            self.isLocalConductor = isLocalConductor
            self.receivedTerminalEvent = receivedTerminalEvent
            self.localTerminalEvent = localTerminalEvent
        }
    }
}
#endif
