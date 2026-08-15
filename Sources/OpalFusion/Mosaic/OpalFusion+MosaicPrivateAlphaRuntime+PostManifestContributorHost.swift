// OpalFusion+MosaicPrivateAlphaRuntime+PostManifestContributorHost.swift

#if os(macOS)
import Foundation
import OpalCrypto

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// Typed wallet and restored-key capabilities for the selected contributor runtime.
    @_spi(MosaicPrivateAlpha)
    public struct PostManifestContributorHost: Sendable {
        let transactionHost: any OpalFusion.Host
            .MosaicCompleteTransactionHost
        let previousOutputSource: any OpalFusion.Host
            .MosaicPreviousOutputSource
        let controlSigningKey: OpalCrypto.Secp256k1.SigningKey
        let controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey
        let loadSlotSecrets: @Sendable (
            Binding,
            OpalFusion.Host.MosaicReservationLease
        ) async throws -> [PostManifestComponentSlotSecrets]

        @_spi(MosaicPrivateAlpha)
        public init(
            transactionHost: any OpalFusion.Host
                .MosaicCompleteTransactionHost,
            previousOutputSource: any OpalFusion.Host
                .MosaicPreviousOutputSource,
            controlSigningKey: OpalCrypto.Secp256k1.SigningKey,
            controlEventSigningKey: OpalCrypto.Secp256k1.SigningKey,
            loadSlotSecrets: @escaping @Sendable (
                Binding,
                OpalFusion.Host.MosaicReservationLease
            ) async throws -> [PostManifestComponentSlotSecrets]
        ) {
            self.transactionHost = transactionHost
            self.previousOutputSource = previousOutputSource
            self.controlSigningKey = controlSigningKey
            self.controlEventSigningKey = controlEventSigningKey
            self.loadSlotSecrets = loadSlotSecrets
        }
    }
}
#endif
