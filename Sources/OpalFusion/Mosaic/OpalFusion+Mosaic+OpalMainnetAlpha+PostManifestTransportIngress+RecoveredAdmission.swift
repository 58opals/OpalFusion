// OpalFusion+Mosaic+OpalMainnetAlpha+PostManifestTransportIngress+RecoveredAdmission.swift

import Foundation

extension OpalFusion.Mosaic.OpalMainnetAlpha.PostManifestTransportIngress {
    /// One exact gift wrap and the durable time at which it was originally authenticated.
    struct RecoveredAdmission: Sendable, Equatable, Hashable {
        let canonicalGiftWrapBytes: Data
        let acceptedAtUnixSeconds: UInt64

        init(
            canonicalGiftWrapBytes: Data,
            acceptedAtUnixSeconds: UInt64
        ) {
            self.canonicalGiftWrapBytes = canonicalGiftWrapBytes
            self.acceptedAtUnixSeconds = acceptedAtUnixSeconds
        }
    }
}
