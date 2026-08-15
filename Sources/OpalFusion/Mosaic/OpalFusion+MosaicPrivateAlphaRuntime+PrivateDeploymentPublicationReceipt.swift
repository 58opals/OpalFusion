// OpalFusion+MosaicPrivateAlphaRuntime+PrivateDeploymentPublicationReceipt.swift

#if os(macOS)
import Foundation

extension OpalFusion.MosaicPrivateAlphaRuntime {
    /// One-use package-minted proof that the exact recorded event reached the two-relay boundary.
    @_spi(MosaicPrivateAlpha)
    public struct PrivateDeploymentPublicationReceipt: ~Copyable, Sendable {
        let operationIdentifier: Data

        init(operationIdentifier: Data) {
            self.operationIdentifier = operationIdentifier
        }
    }
}
#endif
